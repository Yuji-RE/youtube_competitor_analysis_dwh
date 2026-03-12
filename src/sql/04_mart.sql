-- 目的：mart層のテーブルにデータを集計して挿入する
-- 実行順：03_import_and_clean_competitor.sql の後に実行する
-- チャンネル固有キーワードを読み込む（gitignore済み・keywords_template.sql を参照）
\i /sql/keywords.sql

  -- mart.self_weekly: 自チャンネルの週次集計
  INSERT INTO mart.self_weekly (
    week_start,
    total_views,
    total_watch_time_minutes,
    total_subscribers_net,
    total_engaged_views,
    total_likes,
    total_shares,
    total_comments
  )
  SELECT
    DATE_TRUNC('week', date)::DATE,
    SUM(views),
    SUM(watch_time_minutes),
    SUM(subscribers_net),
    SUM(engaged_views),
    SUM(likes),
    SUM(shares),
    SUM(comments_added)
  FROM clean.youtube_self_daily
  GROUP BY DATE_TRUNC('week', date);

  -- mart.competitor_segment: 競合動画のセグメント × 動画タイプ別集計
  -- ショート動画（<=60s）と通常動画（61-600s）を分離することで、
  -- アルゴリズム特性の違いによる平均値の歪みを防ぐ。
  INSERT INTO mart.competitor_segment (
    strategy_segment,
    video_type,
    avg_view_count,
    avg_like_count,
    avg_comment_count,
    avg_duration_seconds,
    video_count,
    avg_channel_subscriber_count
  )
  SELECT
    strategy_segment,
    CASE WHEN duration_seconds <= 60 THEN 'shorts' ELSE 'regular' END AS video_type,
    ROUND(AVG(view_count), 2),
    ROUND(AVG(like_count), 2),
    ROUND(AVG(comment_count), 2),
    ROUND(AVG(duration_seconds), 2),
    COUNT(*),
    ROUND(AVG(channel_subscriber_count), 2)
  FROM clean.youtube_competitor
  WHERE
    :exclude_filter  --除外キーワード (keywords.sql)
    AND duration_seconds <= 600  -- 10分超はライブ配信等のノイズとして除外
    AND strategy_segment != 'footage_search'  -- footage_searchはYouTube API検索精度の問題でノイズが多く除外
    AND (
      (strategy_segment = 'own_strategy' AND :own_strategy_filter)  --OWN_ATTRIBUTE (keywords.sql)
      OR (strategy_segment = 'mainstream' AND :mainstream_filter)   --MAINSTREAM_ATTRIBUTE (keywords.sql)
    )
  GROUP BY strategy_segment, video_type;

  -- mart.strategy_comparison: 自チャンネル vs 競合セグメントの比較
  -- CTE ベースで構成することで、登録者数補正カラムを段階的に計算する。
  WITH self_subs AS (
    -- 自チャンネルの最新登録者数を取得
    SELECT channel_subscribers::INTEGER AS cnt
    FROM raw.youtube_self_daily
    WHERE channel_subscribers IS NOT NULL AND channel_subscribers != ''
    ORDER BY date_raw DESC LIMIT 1
  ),
  competitor_base AS (
    -- PADフィルタ・ジャンルフィルタ・10分超フィルタ適用済みの競合動画
    SELECT
      strategy_segment,
      title,
      view_count,
      like_count,
      comment_count,
      duration_seconds,
      channel_subscriber_count,
      CASE WHEN duration_seconds <= 60 THEN 'shorts' ELSE 'regular' END AS video_type
    FROM clean.youtube_competitor
    WHERE
      :exclude_filter  --除外キーワード (keywords.sql)
      AND duration_seconds <= 600
      AND strategy_segment != 'footage_search'
      AND (
        (strategy_segment = 'own_strategy' AND :own_strategy_filter)  --OWN_ATTRIBUTE (keywords.sql)
        OR (strategy_segment = 'mainstream' AND :mainstream_filter)   --MAINSTREAM_ATTRIBUTE (keywords.sql)
      )
  ),
  competitor_agg AS (
    -- セグメント × video_type で集計
    SELECT
      strategy_segment,
      video_type,
      ROUND(AVG(view_count), 2)               AS avg_view_count,
      ROUND(AVG(like_count), 2)               AS avg_like_count,
      ROUND(AVG(comment_count), 2)            AS avg_comment_count,
      ROUND(AVG(duration_seconds), 2)         AS avg_duration_seconds,
      COUNT(*)                                AS video_count,
      ROUND(AVG(channel_subscriber_count), 2) AS avg_channel_subscriber_count
    FROM competitor_base
    GROUP BY strategy_segment, video_type
  ),
  similar_scale_agg AS (
    -- 登録者数 ≤ 400 のチャンネルに絞った集計（自チャンネル201人がほぼ中央値となる範囲）
    SELECT
      strategy_segment,
      video_type,
      ROUND(AVG(view_count), 2) AS similar_scale_avg_view_count,
      COUNT(*)                  AS similar_scale_video_count
    FROM competitor_base
    WHERE channel_subscriber_count <= 400
    GROUP BY strategy_segment, video_type
  )
  INSERT INTO mart.strategy_comparison (
    segment,
    video_type,
    avg_view_count,
    avg_like_count,
    avg_comment_count,
    avg_duration_seconds,
    video_count,
    avg_channel_subscriber_count,
    normalized_avg_view_count,
    similar_scale_avg_view_count,
    similar_scale_video_count
  )
  -- 競合セグメント行
  SELECT
    ca.strategy_segment AS segment,
    ca.video_type,
    ca.avg_view_count,
    ca.avg_like_count,
    ca.avg_comment_count,
    ca.avg_duration_seconds,
    ca.video_count,
    ca.avg_channel_subscriber_count,
    CASE WHEN ca.video_type = 'regular'
      THEN ROUND(ca.avg_view_count / NULLIF(ca.avg_channel_subscriber_count, 0) * ss.cnt, 2)
      ELSE NULL  -- ショートは登録者数との相関が低いため非適用
    END AS normalized_avg_view_count,
    ssa.similar_scale_avg_view_count,
    ssa.similar_scale_video_count
  FROM competitor_agg ca
  CROSS JOIN self_subs ss
  LEFT JOIN similar_scale_agg ssa
    ON ca.strategy_segment = ssa.strategy_segment AND ca.video_type = ssa.video_type
  UNION ALL
  -- 自チャンネル行: normalized=NULL（自身が基準）、similar_scale=avg_view_count（自身が同規模）
  --チャンネル固有設定：GENRE_KEYWORDS (.env を参照)
  SELECT
    'self' AS segment,
    CASE WHEN duration_seconds <= 60 THEN 'shorts' ELSE 'regular' END AS video_type,
    ROUND(AVG(view_count), 2)       AS avg_view_count,
    ROUND(AVG(like_count), 2)       AS avg_like_count,
    ROUND(AVG(comment_count), 2)    AS avg_comment_count,
    ROUND(AVG(duration_seconds), 2) AS avg_duration_seconds,
    COUNT(*)                        AS video_count,
    ss.cnt                          AS avg_channel_subscriber_count,
    NULL                            AS normalized_avg_view_count,
    ROUND(AVG(view_count), 2)       AS similar_scale_avg_view_count,
    COUNT(*)                        AS similar_scale_video_count
  FROM clean.youtube_self_content
  CROSS JOIN self_subs ss
  WHERE duration_seconds <= 600
  GROUP BY video_type, ss.cnt;
