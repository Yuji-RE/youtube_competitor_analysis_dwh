-- 目的：YouTube Analytics CSV を raw 層にインポートし、clean 層に変換する
-- 実行順：01_create_tables.sql の後に実行する

-- importing to raw layer

\COPY raw.youtube_self_daily FROM '/data/raw/daily/totals_clean.csv' WITH ( FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');

-- cleaning data and inserting into clean layer
INSERT INTO clean.youtube_self_daily (
    date,
    views,
    watch_time_minutes,
    subscribers_net,
    engaged_views,
    impressions,
    impression_ctr,
    likes,
    shares,
    comments_added
)
SELECT
    date_raw::DATE,
    views::INTEGER,
    ROUND((watch_time_hours::NUMERIC) * 60, 2),
    subscribers_gained::INTEGER - subscribers_lost::INTEGER,
    engaged_views::INTEGER,
    impressions::INTEGER,
    impression_ctr::NUMERIC,
    likes::INTEGER,
    shares::INTEGER,
    comments_added::INTEGER
FROM raw.youtube_self_daily
WHERE date_raw ~ '^\d{4}-\d{2}-\d{2}$';

-- youtube_self_content: 動画単位データのインポート
\COPY raw.youtube_self_content FROM '/data/raw/content/totals.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');

INSERT INTO clean.youtube_self_content (
    video_id,
    title,
    published_at,
    duration_seconds,
    view_count,
    like_count,
    comment_count,
    shares,
    engaged_views,
    subscribers_net,
    impressions,
    impression_ctr
)
SELECT
    video_id,
    title,
    TO_DATE(published_at, 'Mon DD, YYYY'),  -- "Sep 4, 2024" 形式を DATE に変換
    NULLIF(duration_seconds, '')::INTEGER,
    NULLIF(view_count, '')::INTEGER,
    NULLIF(like_count, '')::INTEGER,
    NULLIF(comment_count, '')::INTEGER,
    NULLIF(shares, '')::INTEGER,
    NULLIF(engaged_views, '')::INTEGER,
    NULLIF(subscribers_gained, '')::INTEGER
    - NULLIF(subscribers_lost, '')::INTEGER,
    NULLIF(impressions, '')::INTEGER,
    NULLIF(impression_ctr, '')::NUMERIC
FROM raw.youtube_self_content
WHERE
    video_id IS NOT NULL
    AND video_id != '合計';  -- 合計行を除外
