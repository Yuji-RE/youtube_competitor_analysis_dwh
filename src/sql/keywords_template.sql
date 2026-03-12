-- チャンネル固有キーワード設定テンプレート
-- このファイルをコピーして src/sql/keywords.sql を作成し、実際のキーワードを設定する
-- keywords.sql は .gitignore により非公開
--
-- 使い方：
--   \set 変数名 SQL条件式
--   04_mart.sql 内で :変数名 として展開される

-- own_strategy セグメントの包含フィルタ（自チャンネルの差別化属性に関連する動画を絞る）
\set own_strategy_filter '(title ILIKE ''%{OWN_ATTRIBUTE_1}%'' OR title ILIKE ''%{OWN_ATTRIBUTE_2}%'') AND (title ILIKE ''%{SKILL_KEYWORD_1}%'' OR title ILIKE ''%{SKILL_KEYWORD_2}%'')'

-- mainstream セグメントの包含フィルタ（市場の主流属性に関連する動画を絞る）
\set mainstream_filter '(title ILIKE ''%{MAINSTREAM_ATTRIBUTE_1}%'' OR title ILIKE ''%{MAINSTREAM_ATTRIBUTE_2}%'') AND (title ILIKE ''%{SKILL_KEYWORD_1}%'' OR title ILIKE ''%{SKILL_KEYWORD_2}%'')'

-- ジャンルフィルタ（コンテンツ形式の絞り込み）
\set genre_filter '(title ILIKE ''%{GENRE_KW_1}%'' OR title ILIKE ''%{GENRE_KW_2}%'' OR title ILIKE ''%{GENRE_KW_3}%'' OR title ILIKE ''%{GENRE_KW_4}%'')'

-- 除外フィルタ（分析対象外のコンテンツを除外するキーワード）
\set exclude_filter 'title NOT ILIKE ''%{EXCLUDE_KW_1}%'' AND title NOT ILIKE ''%{EXCLUDE_KW_2}%'' AND title NOT ILIKE ''%{EXCLUDE_KW_3}%'''
