# Data Dictionary

分析者向けのビジネス定義・指標の計算ロジック・用語集。
技術的なカラム定義（型・主キー等）は [`table_definitions.md`](table_definitions.md) を参照。

---

## データソース

### ① 自己データ（YouTube Analytics CSV）

| 項目 | 内容 |
|---|---|
| ソース | YouTube Studio からエクスポートしたCSV |
| 期間 | 2022/12 〜 2026/02 |
| 内容 | 日次の視聴回数・視聴時間・登録者増減・インプレッション等（`raw.youtube_self_daily`）、動画単位の各種指標（`raw.youtube_self_content`） |

### ② 競合・市場データ（YouTube Data API v3）

| 収集期間 | 対象 | 本数 |
|---|---|---|
| 過去ベースライン | 2019〜2024/06 公開・同ジャンル動画 | 約600本 |
| 活動期間同期帯 | 2024/07〜2026/02 公開・同ジャンル動画 | 約560本 |

収集クエリ構成（キーワードの実値は `.env` で管理・非公開）：

```python
SEARCH_KEYWORDS = {
    "own_strategy":   [f"{GAME} {OWN_ATTRIBUTE} {SKILL_KEYWORD}"],
    "mainstream":     [f"{GAME} {MAINSTREAM_ATTRIBUTE} {SKILL_KEYWORD}"],
    }
```

収集フィールド: 動画ID・タイトル・投稿日・チャンネルID・チャンネル登録者数・視聴回数・高評価数・コメント数・動画時間・[映像要素]キーワード含有フラグ

---

## スキーマ概要（3層構造）

### raw 層

| テーブル | ソース | 内容 |
|---|---|---|
| `raw.youtube_self_daily` | YouTube Analytics CSV（日次） | 自己チャンネルの日次集計データ（全列 TEXT） |
| `raw.youtube_self_content` | YouTube Analytics CSV（動画別） | 自己チャンネルの動画単位データ（全列 TEXT） |
| `raw.youtube_competitor` | YouTube Data API v3 | 競合・市場動画の収集データ（全列 TEXT） |

### clean 層

| テーブル | 内容 |
|---|---|
| `clean.youtube_self_daily` | 型変換済みの自己日次データ |
| `clean.youtube_self_content` | 型変換済みの自己動画単位データ |
| `clean.youtube_competitor` | 型変換・重複排除済みの競合動画データ |

### mart 層

| テーブル | 内容 |
|---|---|
| `mart.self_weekly` | 自己データの週次集計 |
| `mart.competitor_segment` | 競合を戦略セグメント × 動画タイプ別に集計 |
| `mart.strategy_comparison` | 自己チャンネル vs 競合セグメントの動画単位比較（補正カラム含む） |

---

## セグメント定義

### `strategy_segment`（戦略セグメント）

競合動画を収集する際の検索クエリに基づく分類。収集キーワードの組み合わせによって決まる。

| 値 | 意味 | 収集クエリの構成 |
|---|---|---|
| `own_strategy` | 自チャンネルと同じ差別化戦略をとるクリエイターの動画 | `{GAME} {OWN_ATTRIBUTE} {SKILL_KEYWORD}` |
| `mainstream` | 市場の主流戦略をとるクリエイターの動画 | `{GAME} {MAINSTREAM_ATTRIBUTE} {SKILL_KEYWORD}` |
| `footage_search` | [映像要素]キーワードで収集した動画。YouTube API の検索精度の問題でノイズが多く **mart 集計からは除外**。タイトルに映像キーワードを含む動画が約 3% にとどまることの根拠として `clean` 層に保持 | `{GAME} {SKILL_KEYWORD} {FOOTAGE_KEYWORD}` |
| `self` | 自チャンネルの動画（`mart.strategy_comparison` のみ） | — |

> キーワードの実値は `.env` で管理（リポジトリ非公開）。

---

### `video_type`（動画タイプ）

動画の長さに基づく分類。ショート動画はYouTubeアルゴリズムの特性上、登録者数に関わらず再生数が桁違いに高くなりやすいため、通常動画と混在させると平均値が歪む。この歪みを防ぐために分離している。

| 値 | 条件 | 備考 |
|---|---|---|
| `shorts` | `duration_seconds <= 60` | YouTubeショート相当 |
| `regular` | `61 <= duration_seconds <= 600` | 通常動画（10分以内） |
| （除外） | `duration_seconds > 600` | ライブ配信・長尺動画のノイズとして除外 |

---

## 指標定義

### `normalized_avg_view_count`（正規化平均再生数）

**計算式**:
```
normalized_avg_view_count = avg_view_count / avg_channel_subscriber_count × 自チャンネル登録者数（201）
```

**目的**: チャンネル規模の差を除いた上でのパフォーマンス比較。「競合が自チャンネルと同じ登録者数だったら何再生取れるか」の仮想値。

**適用範囲**: `regular` のみ。`shorts` は NULL。

**理由**: ショート動画はアルゴリズム主導の拡散が支配的であり、登録者数との相関が低いため、線形比例の仮定が成立しない。

**解釈上の注意（`regular`）**: 登録者数と再生数の**線形比例を仮定した参考値**であり、知名度・コンテンツ品質・投稿タイミング・アルゴリズムなど非線形な要因は一切考慮していない。確定的な結論を導くには不十分であり、傾向の示唆として扱うこと。

---

### `similar_scale_avg_view_count` / `similar_scale_video_count`（同規模フィルタ集計）

**定義**: `channel_subscriber_count <= 400` のチャンネルに絞った平均再生数・動画本数。

**閾値の根拠**: 自チャンネルの登録者数（201人）がほぼ中央値となる範囲（0〜400）として選定。登録者数規模を揃えることで、正規化より直接的な同条件比較を実現する。

**適用範囲**: `regular` / `shorts` 両方に適用（`normalized_avg_view_count` が適用できない `shorts` の代替指標として特に有用）。

**解釈上の注意**: セグメントによってはフィルタ後のサンプルサイズが極めて小さくなる（例: `footage_search` の `shorts` は 9 本）。`similar_scale_video_count` を必ず合わせて確認すること。サンプルが少ない場合、1本のバズ動画で平均が大きく歪む。

---

## フィルタリングロジック

### PADフィルタ（競合データ）

`mart` 層の集計時に、コントローラー（パッド）関連コンテンツをタイトルキーワードで除外している。対象ジャンルはマウス操作が前提であり、コントローラー操作の動画は比較対象として不適切なため。

除外キーワード（一部）: `PAD`, `パッド`, `コントローラー`, `PS4`, `PS5`, `Switch`, `Xbox`, `リニア`, `クラシック`, `デッドゾーン`, `応答曲線` など。

### ジャンルフィルタ（GENRE_KEYWORDS）

`.env` の `GENRE_KEYWORDS` に設定したタイトルキーワードに一致する動画のみを集計対象とする**包含フィルタ**。自チャンネルのコンテンツジャンル（クリップ集・キル集系）に絞ることで、解説系・バラエティ系・あるある系などの無関係なコンテンツを排除する。

競合分析の比較対象を「同ジャンルの競合」に絞るための中心的なフィルタ。`mart.competitor_segment` と `mart.strategy_comparison` の両テーブルの全集計に適用される。

- **変更方法**: `.env` の `GENRE_KEYWORDS` を書き換えたうえで、`04_mart.sql` 内の `-- ★ チャンネル固有設定` コメント箇所を同様に更新する

### チートフィルタ（競合データ）

チート販売・ツール販売系のスパムアカウントをタイトルキーワードで除外する。対象：`チート`、`aimbot`、`aim bot`、`販売` など。

### 10分超フィルタ（`duration_seconds > 600`）

ライブ配信・長尺動画のノイズ除去。自チャンネルの投稿コンテンツと性質が大きく異なるため除外。
