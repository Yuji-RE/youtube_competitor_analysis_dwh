-- 目的：競合動画データを raw 層にインポートし、 clean 層に変換する
-- 実行順：collect_competitor.sql を実行した後に実行する

-- raw 層に競合動画データをインポート
\COPY raw.youtube_competitor FROM '/data/raw/competitor/youtube_competitor.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');

-- clean 層に競合動画データを変換して挿入
INSERT INTO clean.youtube_competitor(
  video_id,
  title,
  published_at,
  channel_id,
  channel_title,
  channel_subscriber_count,
  view_count,
  like_count,
  comment_count,
  duration_seconds,
  strategy_segment,
  collected_at
)
SELECT DISTINCT ON (video_id, strategy_segment)
  video_id,
  title,
  published_at::DATE,
  channel_id,
  channel_title,
  NULLIF(channel_subscriber_count, '')::INTEGER,
  NULLIF(view_count, '')::INTEGER,  -- 空文字を NULL に変換してから整数にキャスト（空の行でエラーをださないために）
  NULLIF(like_count, '')::INTEGER,
  NULLIF(comment_count, '')::INTEGER,
  -- ISO 8601 duration (例：PT8M38S) を秒数に変換
  EXTRACT(EPOCH FROM NULLIF(duration, '')::INTERVAL)::INTEGER,
  strategy_segment,
  collected_at::TIMESTAMP
FROM raw.youtube_competitor
WHERE video_id IS NOT NULL
  AND title IS NOT NULL
ORDER BY video_id, strategy_segment;
