# テーブル定義

各レイヤーの主要テーブルのカラム定義。

---

## clean 層

### clean.youtube_self_daily

| column | type | description |
|--------|------|-------------|
| date | DATE | 日付（主キー） |
| views | INTEGER | 視聴回数 |
| watch_time_minutes | NUMERIC | 総視聴時間（分） |
| subscribers_net | INTEGER | 登録者増減（増加 - 減少） |
| engaged_views | INTEGER | エンゲージビュー |
| impressions | INTEGER | インプレッション数 |
| impression_ctr | NUMERIC | クリック率 (%) |
| likes | INTEGER | 高評価数 |
| shares | INTEGER | 共有数 |
| comments_added | INTEGER | コメント数 |

### clean.youtube_self_content

| column | type | description |
|--------|------|-------------|
| video_id | TEXT | 動画ID（主キー） |
| title | TEXT | 動画タイトル |
| published_at | DATE | 投稿日 |
| duration_seconds | INTEGER | 動画時間（秒） |
| view_count | INTEGER | 視聴回数 |
| like_count | INTEGER | 高評価数 |
| comment_count | INTEGER | コメント数 |
| shares | INTEGER | 共有数 |
| engaged_views | INTEGER | エンゲージビュー |
| subscribers_net | INTEGER | 登録者増減 |
| impressions | INTEGER | インプレッション数 |
| impression_ctr | NUMERIC | クリック率 (%) |

### clean.youtube_competitor

| column | type | description |
|--------|------|-------------|
| video_id | TEXT | 動画ID（strategy_segment との複合主キー） |
| title | TEXT | 動画タイトル |
| published_at | DATE | 投稿日 |
| channel_id | TEXT | チャンネルID |
| channel_subscriber_count | INTEGER | チャンネル登録者数（収集時点） |
| view_count | INTEGER | 視聴回数 |
| like_count | INTEGER | 高評価数 |
| comment_count | INTEGER | コメント数 |
| duration_seconds | INTEGER | 動画時間（秒） |
| strategy_segment | TEXT | 戦略セグメント分類（own_strategy / mainstream / footage_search）（video_id との複合主キー） |
| collected_at | TIMESTAMP | 収集日時 |

---

## mart 層

### mart.competitor_segment

| column | type | description |
|--------|------|-------------|
| strategy_segment | TEXT | 戦略セグメント（主キー） |
| video_type | TEXT | 動画タイプ: `shorts`（≦60s）/ `regular`（61-600s）（主キー） |
| avg_view_count | NUMERIC | 平均視聴回数 |
| avg_like_count | NUMERIC | 平均高評価数 |
| avg_comment_count | NUMERIC | 平均コメント数 |
| avg_duration_seconds | NUMERIC | 平均動画時間（秒） |
| video_count | INTEGER | 動画本数 |
| avg_channel_subscriber_count | NUMERIC | セグメント内チャンネルの平均登録者数 |

### mart.strategy_comparison

| column | type | description |
|--------|------|-------------|
| segment | TEXT | セグメント名（`self` または 戦略セグメント名）（主キー） |
| video_type | TEXT | 動画タイプ: `shorts`（≦60s）/ `regular`（61-600s）（主キー） |
| avg_view_count | NUMERIC | 平均視聴回数 |
| avg_like_count | NUMERIC | 平均高評価数 |
| avg_comment_count | NUMERIC | 平均コメント数 |
| avg_duration_seconds | NUMERIC | 平均動画時間（秒） |
| video_count | INTEGER | 動画本数 |
| avg_channel_subscriber_count | NUMERIC | セグメント内チャンネルの平均登録者数 |
| normalized_avg_view_count | NUMERIC | 自登録者数で正規化した仮想平均再生数（`regular` のみ、線形比例を仮定した参考値） |
| similar_scale_avg_view_count | NUMERIC | 登録者数≤400チャンネルに絞った平均再生数 |
| similar_scale_video_count | INTEGER | 同規模フィルタ後の動画数 |
