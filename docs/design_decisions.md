## 設計の試行錯誤

### ③ ショート動画と通常動画の分離

品質チェックの結果、`mart.competitor_segment` の `footage_search` セグメントで `avg_duration_seconds` が約53分という異常値が検出された。原因はライブ配信や長尺動画の混入だった。

さらに分析すると、**ショート動画（≦60秒）は通常動画の10〜20倍の平均再生数**を持つことが判明。ショートはYouTubeアルゴリズムの特性上、再生数が桁違いに高くなりやすく、混在させると平均値が歪む。

対応として：
- 10分超（600秒超）の動画をフィルタで除外
- `mart.competitor_segment` と `mart.strategy_comparison` に `video_type`（`shorts` / `regular`）カラムを追加し、2軸で集計する設計に変更

### ④ 登録者数補正カラムの追加

`mart.strategy_comparison` の直接比較は、チャンネル規模差（自チャンネル201人 vs 競合中央値2,160人、最大268万人）により信憑性が低い。分析者が多角的に比較できるよう、2軸の補正カラムを追加した。

**正規化（全体参考値）— `normalized_avg_view_count`**
- 計算式：`avg_view_count / avg_channel_subscriber_count × 自チャンネル登録者数（201）`
- 「競合が自チャンネルと同じ登録者数だったら何再生取れるか」の仮想値（線形比例を仮定した参考値）
- `regular` のみに適用。ショートはアルゴリズム主導で登録者数との相関が低いため NULL とする

**同規模フィルタ（信憑性ある比較）— `similar_scale_avg_view_count` / `similar_scale_video_count`**
- 登録者数 ≤ 400 のチャンネルに絞った集計（自チャンネル 201 人がほぼ中央値となる範囲）
- 自チャンネル（201人）に近い規模に絞ることで比較の前提を揃える

あわせて `04_mart.sql` の `strategy_comparison` INSERT を CTE ベースに再構成し、集計ロジックの見通しを改善した。

### ⑤ `has_footage` の命名衝突と `footage_search` へのリネーム

実装後に `strategy_segment` の値 `has_footage` と boolean カラム `has_footage` が同名になっていることが判明した。
README やクエリ結果を読む際に「セグメントの話か、フラグの話か」が文脈なしに判別できず、混乱を招く命名だった。

対応として `strategy_segment` の値を `footage_search`（映像キーワードで収集したセグメント）にリネームし、
boolean カラム `has_footage`（タイトルに映像キーワードが含まれるか）と明確に区別できるようにした。

あわせて、`footage_search` セグメントの `similar_scale_avg_view_count`（同規模フィルタ）が shorts で 80,592 という
突出した値を示していることも確認した。これは同フィルタ後のサンプルが **9本のみ** であり、
1本のバズ動画で平均が大きく歪む規模である。比較表では注記付きで掲載しているが、統計的信頼性は低い。

### ⑥ `clean.youtube_competitor` の主キー設計見直し

当初 `clean.youtube_competitor` の主キーを `video_id` 単独に設定していた。しかし `footage_search` セグメントは
[差別化戦略] / [主流戦略] どちらの戦略とも重複しうる戦略横断的なセグメントであり、同一動画が複数セグメントに
属するケースが存在する。`video_id` 単独の主キーでは `DISTINCT ON (video_id)` によって重複行が1件に潰され、
`footage_search` に本来カウントされるべき動画が除外される問題があった。

なお、[差別化戦略] と [主流戦略] は排反する要素であるため、`own_strategy` と `mainstream` 間の重複は
構造的に発生しない。問題は `footage_search` との重複のみである。

対応として主キーを `(video_id, strategy_segment)` の複合キーに変更し、1動画が複数セグメントに属せる設計にした。
あわせて `DISTINCT ON (video_id, strategy_segment) ... ORDER BY video_id, strategy_segment` に修正し、
品質チェックの重複検出も `GROUP BY video_id, strategy_segment` に更新した。

### ⑦ `has_footage` カラムの廃止

`has_footage`（タイトルに映像要素キーワードが含まれるかの boolean フラグ）を `clean.youtube_competitor` から削除した。

廃止理由：実データを確認したところ、`footage_search` セグメント 235 本中 `has_footage = TRUE` はわずか **12本**（約5%）にとどまった。タイトルにキーワードを明記するクリエイターが少数であるため、タイトルキーワード判定では実際に映像要素を含む動画の大半を検出できない構造的限界があった。フラグを維持しても分析上の意味をなさないと判断し削除した。

### ⑧ ジャンルフィルタ集計カラムの追加

全体規模を維持しつつ、自チャンネルのコンテンツジャンルに特化した集計を `mart` 層に追加した。
【背景】競合の集計には、自チャンネルとは異なるジャンルの動画も含まれていたため、フィルタリング条件をより厳しく設定する必要があった。

**追加カラム — `genre_avg_view_count` / `genre_video_count`**（`mart.competitor_segment` と `mart.strategy_comparison` の両テーブル）
- `.env` の `GENRE_KEYWORDS` に設定したタイトルキーワードに該当する動画だけのサブセット集計
- 全体集計（`avg_view_count` / `video_count`）は変更せず、横に並べる形で追加
- `similar_scale_*` が登録者数軸でのサブセットであるのに対し、`genre_*` はコンテンツ内容軸でのサブセット
- チャンネル固有のキーワードは `.env` の `GENRE_KEYWORDS` で管理し、`04_mart.sql` の `-- ★ チャンネル固有設定` コメント箇所を変更することで他チャンネルにも転用可能な設計にした

### ⑨ `footage_search` セグメントの mart 集計除外

`footage_search` セグメント（`{GAME} {SKILL_KEYWORD} {FOOTAGE_KEYWORD}` で収集）を `mart.competitor_segment` と `mart.strategy_comparison` の集計対象から除外した。

**除外理由：YouTube Data API の検索精度の問題**

YouTube Data API の検索は完全一致ではなく関連度スコアで動画を返す。収集した全 1,347 本中、タイトルやタグにキーワードを含む動画はわずか **16 本（約 1%）** にとどまった。`footage_search` セグメント（350 本）に限っても 12 本であり、セグメントとして意図した母集団を捉えられていない。

さらに `footage_search` は `own_strategy` / `mainstream` のような属性キーワードによる絞り込みがないため、クエリ条件を満たさないフォロワー数の大きいチャンネルが混入しやすく、中央値登録者数が他セグメントの約 10〜17 倍（25,100 人 vs 2,860 / 1,480 人）に達していた。このままインサイトに含めると比較の前提が崩れるため、集計から除外することにした。

そこで、footage_search のデータは `clean.youtube_competitor` に保持し、「タイトルキーワードによる手元映像検出の限界」の根拠数値（全 1,347 本中 16 本 = 約 1%）として参照するにとどめる。手元映像の定量検出はサムネイル・動画フレームの ML 解析が必要であり、本プロジェクトのスコープ外とする。
