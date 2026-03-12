-- 目的：データ品質チェック
-- 実行順：04_mart.sql の後に実行する
-- 1. 件数確認
SELECT
  'raw.youtube_self_daily' AS table_name,
  COUNT(*) AS row_count
FROM
  raw.youtube_self_daily
UNION ALL
SELECT
  'clean.youtube_self_daily' AS table_name,
  COUNT(*) AS row_count
FROM
  clean.youtube_self_daily
UNION ALL
SELECT
  'raw.youtube_self_content' AS table_name,
  COUNT(*) AS row_count
FROM
  raw.youtube_self_content
UNION ALL
SELECT
  'clean.youtube_self_content' AS table_name,
  COUNT(*) AS row_count
FROM
  clean.youtube_self_content
UNION ALL
SELECT
  'raw.youtube_competitor' AS table_name,
  COUNT(*) AS row_count
FROM
  raw.youtube_competitor
UNION ALL
SELECT
  'clean.youtube_competitor' AS table_name,
  COUNT(*) AS row_count
FROM
  clean.youtube_competitor
UNION ALL
SELECT
  'mart.self_weekly' AS table_name,
  COUNT(*) AS row_count
FROM
  mart.self_weekly
UNION ALL
SELECT
  'mart.competitor_segment' AS table_name,
  COUNT(*) AS row_count
FROM
  mart.competitor_segment
UNION ALL
SELECT
  'mart.strategy_comparison' AS table_name,
  COUNT(*) AS row_count
FROM
  mart.strategy_comparison;

-- 2. clean.youtube_self_daily にNULLがないか
SELECT
  COUNT(*) AS null_count
FROM
  clean.youtube_self_daily
WHERE
  date IS NULL
  OR views IS NULL
  OR watch_time_minutes IS NULL;

-- 3. clean.youtube_competitor の重複チェック（同一セグメント内の重複のみ検出）
SELECT
  video_id,
  strategy_segment,
  COUNT(*) AS cnt
FROM
  clean.youtube_competitor
GROUP BY
  video_id,
  strategy_segment
HAVING
  COUNT(*) > 1;

-- 4. mart.strategy_comparison の内容確認（自己 vs 競合セグメント）
SELECT
  *
FROM
  mart.strategy_comparison
ORDER BY
  segment;
