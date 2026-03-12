-- 目的：全スキーマ・全レイヤーのテーブルを作成する
-- 実行順：このフォルダ内で最初に実行する
-- IF NOT EXISTS を使うことで、スキーマが既に存在してもエラーにならず、複数回実行できる
CREATE SCHEMA IF NOT EXISTS raw;

CREATE SCHEMA IF NOT EXISTS clean;

CREATE SCHEMA IF NOT EXISTS mart;

-- DROP TABLE IF EXISTS を使うことで、テーブルが既に存在する場合は一度削除してから再作成する
-- これにより、テーブルが既存でもエラーなく複数回実行できる
--
-- raw 層のテーブル
DROP TABLE IF EXISTS raw.youtube_self_daily;

CREATE TABLE raw.youtube_self_daily (
  date_raw TEXT,
  core_viewers TEXT,
  engaged_views TEXT,
  channel_subscribers TEXT,
  avg_playback_pct TEXT,
  videos_added TEXT,
  videos_published TEXT,
  impressions TEXT,
  impression_ctr TEXT,
  retention_pct TEXT,
  unique_viewers TEXT,
  avg_views_per_viewer TEXT,
  new_viewers TEXT,
  returning_viewers TEXT,
  light_viewers TEXT,
  subscribers_gained TEXT,
  subscribers_lost TEXT,
  likes TEXT,
  dislikes TEXT,
  like_rate_pct TEXT,
  shares TEXT,
  comments_added TEXT,
  card_clicks TEXT,
  card_impressions TEXT,
  card_ctr TEXT,
  teaser_clicks TEXT,
  teaser_impressions TEXT,
  teaser_ctr TEXT,
  endscreen_clicks TEXT,
  endscreen_impressions TEXT,
  endscreen_ctr TEXT,
  views TEXT,
  watch_time_hours TEXT,
  avg_view_duration TEXT
);

-- raw.youtube_competitor
-- ソース：YouTube Data API v3
DROP TABLE IF EXISTS raw.youtube_competitor;

CREATE TABLE raw.youtube_competitor (
  video_id TEXT,
  title TEXT,
  published_at TEXT,
  channel_id TEXT,
  channel_title TEXT,
  channel_subscriber_count TEXT,
  view_count TEXT,
  like_count TEXT,
  comment_count TEXT,
  duration TEXT, -- ISO 8601 形式（例：PT15M33S = 15分33秒）
  strategy_segment TEXT, -- own_strategy / mainstream / footage_search
  has_footage TEXT,
  collected_at TEXT
);

-- raw.youtube_self_content
-- ソース：YouTube Analytics CSV（動画単位）
DROP TABLE IF EXISTS raw.youtube_self_content;

CREATE TABLE raw.youtube_self_content (
  video_id TEXT,
  title TEXT,
  published_at TEXT,
  duration_seconds TEXT,
  subscribers_gained TEXT,
  subscribers_lost TEXT,
  like_count TEXT,
  dislike_count TEXT,
  like_rate_pct TEXT,
  shares TEXT,
  comment_count TEXT,
  engaged_views TEXT,
  avg_playback_pct TEXT,
  retention_pct TEXT,
  view_count TEXT,
  watch_time_hours TEXT,
  channel_subscribers TEXT,
  avg_view_duration TEXT,
  impressions TEXT,
  impression_ctr TEXT
);

-- clean 層のテーブル
DROP TABLE IF EXISTS clean.youtube_self_daily;

CREATE TABLE clean.youtube_self_daily (
  date DATE,
  views INTEGER,
  watch_time_minutes NUMERIC,
  subscribers_net INTEGER, -- 登録者増減（subscribers_gained - subscribers_lost）。02_import_and_clean_self.sql で計算
  engaged_views INTEGER,
  impressions INTEGER,
  impression_ctr NUMERIC,
  likes INTEGER,
  shares INTEGER,
  comments_added INTEGER,
  PRIMARY KEY (date)
);

-- clean.youtube_self_content
DROP TABLE IF EXISTS clean.youtube_self_content;

CREATE TABLE clean.youtube_self_content (
  video_id TEXT NOT NULL,
  title TEXT,
  published_at DATE,
  duration_seconds INTEGER,
  view_count INTEGER,
  like_count INTEGER,
  comment_count INTEGER,
  shares INTEGER,
  engaged_views INTEGER,
  subscribers_net INTEGER,
  impressions INTEGER,
  impression_ctr NUMERIC,
  PRIMARY KEY (video_id)
);

-- clean.youtube_competitor
DROP TABLE IF EXISTS clean.youtube_competitor;

CREATE TABLE clean.youtube_competitor (
  video_id TEXT NOT NULL,
  title TEXT,
  published_at DATE,
  channel_id TEXT,
  channel_title TEXT,
  channel_subscriber_count INTEGER,
  view_count INTEGER,
  like_count INTEGER,
  comment_count INTEGER,
  duration_seconds INTEGER,
  strategy_segment TEXT,
  collected_at TIMESTAMP,
  PRIMARY KEY (video_id, strategy_segment) -- footageが他のセグメントと重複しうるため複合キー（主流／差別化アプローチは排反要素より問題なし）
);

-- mart.self_weekly: 日次データは変動が大きく単体では読みにくいため、週次で集計して全体トレンドを把握しやすくする
DROP TABLE IF EXISTS mart.self_weekly;

CREATE TABLE mart.self_weekly (
  week_start DATE NOT NULL,
  total_views BIGINT,
  total_watch_time_minutes NUMERIC,
  total_subscribers_net INTEGER,
  total_engaged_views BIGINT,
  total_likes INTEGER,
  total_shares INTEGER,
  total_comments INTEGER,
  PRIMARY KEY (week_start)
);

-- mart.competitor_segment
-- video_type を軸に加えることで、ショート動画と通常動画を分離して集計する。
-- ショート動画はアルゴリズムの恩恵で再生数が桁違いに高くなりやすく、
-- 混在させると平均値が歪むため、比較の前提を揃える目的で分離している。
DROP TABLE IF EXISTS mart.competitor_segment;

CREATE TABLE mart.competitor_segment (
  strategy_segment TEXT NOT NULL,
  video_type TEXT NOT NULL, -- 'shorts' (<=60s) / 'regular' (61-600s)
  avg_view_count NUMERIC,
  avg_like_count NUMERIC,
  avg_comment_count NUMERIC,
  avg_duration_seconds NUMERIC,
  video_count INTEGER,
  avg_channel_subscriber_count NUMERIC, -- セグメント内チャンネルの平均登録者数
  PRIMARY KEY (strategy_segment, video_type)
);

-- mart.strategy_comparison
-- 同上の理由で video_type を軸に加え、自チャンネルと競合を同じ粒度で比較できるようにする。
DROP TABLE IF EXISTS mart.strategy_comparison;

CREATE TABLE mart.strategy_comparison (
  segment TEXT NOT NULL,
  video_type TEXT NOT NULL, -- 'shorts' (<=60s) / 'regular' (61-600s)
  avg_view_count NUMERIC,
  avg_like_count NUMERIC,
  avg_comment_count NUMERIC,
  avg_duration_seconds NUMERIC,
  video_count INTEGER,
  avg_channel_subscriber_count NUMERIC, -- セグメント内チャンネルの平均登録者数
  normalized_avg_view_count NUMERIC, -- 自登録者数で正規化した仮想平均再生数（regular のみ、参考値。線形比例を仮定）
  similar_scale_avg_view_count NUMERIC, -- 登録者数≤400チャンネルに絞った平均再生数
  similar_scale_video_count INTEGER,    -- 同規模フィルタ後の動画数
  PRIMARY KEY (segment, video_type)
);
