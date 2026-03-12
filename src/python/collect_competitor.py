# %% ライブラリをインポート
import os
import csv
import json
import time
import itertools
from datetime import datetime
from dotenv import load_dotenv
from googleapiclient.discovery import build

# %%
# .env から API キーを読み込む
load_dotenv()
YOUTUBE_API_KEY = os.getenv("YOUTUBE_API_KEY")

# 検索クエリ用（全キーワードリスト）
GAME = os.getenv("GAME")
OWN_ATTRIBUTES    = [kw.strip() for kw in os.getenv("OWN_ATTRIBUTE").split(",")]
MAINSTREAM_ATTRS  = [kw.strip() for kw in os.getenv("MAINSTREAM_ATTRIBUTE").split(",")]
SKILL_KEYWORDS    = [kw.strip() for kw in os.getenv("SKILL_KEYWORDS").split(",")]

# タイトルフィルタ用（全表記バリエーション）
GAME_TITLE_KEYWORDS = [kw.strip() for kw in os.getenv("GAME_TITLE_KEYWORDS").split(",")]

# %%
# 定数設定：全キーワードの直積でクエリを生成
SEARCH_KEYWORDS = {
    "own_strategy": [
        f"{GAME} {attr} {skill}"
        for attr, skill in itertools.product(OWN_ATTRIBUTES, SKILL_KEYWORDS)
    ],
    "mainstream": [
        f"{GAME} {attr} {skill}"
        for attr, skill in itertools.product(MAINSTREAM_ATTRS, SKILL_KEYWORDS)
    ],
}

# 1 クエリあたりの最大取得件数（YouTube API の制限に基づく）
MAX_RESUTLS_PER_QUERY = 50
OUTPUT_FILE   = "data/raw/competitor/youtube_competitor.csv"
PROGRESS_FILE = "data/raw/competitor/progress.json"


# %%
# YouTube Data API クライアントを初期化
# 毎回接続情報を作成するのは非効率なので、関数化して必要なときに呼び出せるようにする
def get_youtube_client():
    return build("youtube", "v3", developerKey=YOUTUBE_API_KEY)


# %%
# YouTube から動画を検索して情報を取得する関数
def search_videos(youtube, query, segment, published_after, published_before):
    videos = []
    # 全ページを取得する（1クエリあたり最大 500 件）
    # クォータ消費が大きいため、1日 10,000 ユニットの上限内で完了しない場合は
    # 複数日に分けて実行する（progress.json により途中再開が可能）
    next_page_token = None

    while True:
        response = (
            youtube.search()
            .list(
                q=query,
                part="id,snippet",
                type="video",
                maxResults=MAX_RESUTLS_PER_QUERY,
                publishedAfter=published_after,
                publishedBefore=published_before,
                regionCode="JP",
                relevanceLanguage="ja",
                pageToken=next_page_token,
            )
            .execute()
        )

        for item in response["items"]:
            videos.append(
                {
                    "video_id": item["id"]["videoId"],
                    "title": item["snippet"]["title"],
                    "published_at": item["snippet"]["publishedAt"][:10],
                    "channel_id": item["snippet"]["channelId"],
                    "channel_title": item["snippet"]["channelTitle"],
                    "strategy_segment": segment,
                }
            )

        next_page_token = response.get("nextPageToken")
        if not next_page_token:
            break
        time.sleep(0.5)

    return videos


# %%
"""
# 動画の統計情報を取得する関数

下記の関数では、`videos.list` API の「1回のリクエストで受け取れる最大件数：50件」
を越えてしまうため、動画 ID を 50 件ずつに分割して複数回リクエストする必要がある。

def get_video_stats(youtube, video_ids):
    response = (
        youtube.videos()
        .list(part="statistics,contentDetails", id=",".join(video_ids))
        .execute()
    )

    stats = {}
    for item in response["items"]:
        vid = item["id"]
        s = item["statistics"]
        d = item["contentDetails"]["duration"]
        stats[vid] = {
            "view_count": int(s.get("viewCount", 0)),
            "like_count": int(s.get("likeCount", 0)),
            "comment_count": int(s.get("commentCount", 0)),
            "duration": d,
        }
    return stats
"""

# 動画 ID を 50 件ずつに分割して統計情報を取得する関数


def get_video_stats(youtube, video_ids):
    stats = {}

    for i in range(0, len(video_ids), 50):
        chunk = video_ids[i : i + 50]
        response = (
            youtube.videos()
            .list(part="statistics,contentDetails", id=",".join(chunk))
            .execute()
        )

        for item in response["items"]:
            vid = item["id"]
            s = item["statistics"]
            d = item["contentDetails"]["duration"]
            stats[vid] = {
                "view_count": int(s.get("viewCount", 0)),
                "like_count": int(s.get("likeCount", 0)),
                "comment_count": int(s.get("commentCount", 0)),
                "duration": d,
            }

    return stats


# チャンネル ID を 50 件ずつに分割してチャンネル登録者数を取得する関数
def get_channel_subscriber_counts(youtube, channel_ids):
    counts = {}
    unique_ids = list(set(channel_ids))

    for i in range(0, len(unique_ids), 50):
        chunk = unique_ids[i : i + 50]
        response = (
            youtube.channels().list(part="statistics", id=",".join(chunk)).execute()
        )

        for item in response["items"]:
            cid = item["id"]
            counts[cid] = int(item["statistics"].get("subscriberCount", 0))

    return counts


# %%
# 進捗ファイルの読み書き
def load_progress():
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE, "r", encoding="utf-8") as f:
            return set(json.load(f))
    return set()

def save_progress(done_keys):
    os.makedirs(os.path.dirname(PROGRESS_FILE), exist_ok=True)
    with open(PROGRESS_FILE, "w", encoding="utf-8") as f:
        json.dump(list(done_keys), f, ensure_ascii=False)


# 結果を CSV に追記する関数
FIELDNAMES = [
    "video_id",
    "title",
    "published_at",
    "channel_id",
    "channel_title",
    "channel_subscriber_count",
    "view_count",
    "like_count",
    "comment_count",
    "duration",
    "strategy_segment",
    "collected_at",
]

def append_to_csv(videos, filepath):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    write_header = not os.path.exists(filepath)
    with open(filepath, "a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDNAMES)
        if write_header:
            writer.writeheader()
        writer.writerows(videos)


# %%
# 結果を CSV に書き出す関数（全件まとめて上書き保存・最終dedup用）
def save_to_csv(videos, filepath):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDNAMES)
        writer.writeheader()
        writer.writerows(videos)

    print(f"データを {len(videos)} 件、{filepath} に保存しました。")


# %%
# メイン処理の関数
def main():
    youtube = get_youtube_client()
    collected_at = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")

    periods = {
        "baseline": ("2019-01-01T00:00:00Z", "2024-06-30T23:59:59Z"),
        "active":   ("2024-07-01T00:00:00Z", "2026-02-28T23:59:59Z"),
    }

    done_keys = load_progress()
    total = sum(len(q) for q in SEARCH_KEYWORDS.values()) * len(periods)
    print(f"進捗: {len(done_keys)}/{total} クエリ完了済み")

    for segment, queries in SEARCH_KEYWORDS.items():
        for query in queries:
            for period_name, (after, before) in periods.items():
                key = f"{segment}|{query}|{period_name}"
                if key in done_keys:
                    print(f"スキップ: {query} / {period_name}")
                    continue

                print(f"検索中: {query} / {period_name}")
                videos = search_videos(youtube, query, segment, after, before)

                video_ids = [v["video_id"] for v in videos]
                stats = get_video_stats(youtube, video_ids)

                channel_ids = [v["channel_id"] for v in videos]
                subscriber_counts = get_channel_subscriber_counts(youtube, channel_ids)

                # ゲームタイトルがタイトルに含まれない動画を除外（APIの関連度検索によるノイズ除去）
                videos = [v for v in videos if any(kw in v["title"] for kw in GAME_TITLE_KEYWORDS)]

                for v in videos:
                    vid = v["video_id"]
                    v.update(stats.get(vid, {}))
                    v["channel_subscriber_count"] = subscriber_counts.get(v["channel_id"], 0)
                    v["collected_at"] = collected_at

                append_to_csv(videos, OUTPUT_FILE)
                done_keys.add(key)
                save_progress(done_keys)
                time.sleep(1)

    # 全クエリ完了後: video_id で重複除去して上書き保存
    print("全クエリ完了。重複除去中...")
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        all_videos = list(reader)

    seen_ids = set()
    deduped = []
    for v in all_videos:
        if v["video_id"] not in seen_ids:
            seen_ids.add(v["video_id"])
            deduped.append(v)
    print(f"重複除去: {len(all_videos)} 件 → {len(deduped)} 件")

    save_to_csv(deduped, OUTPUT_FILE)

    # 完了したら進捗ファイルを削除
    os.remove(PROGRESS_FILE)
    print("収集完了。")


if __name__ == "__main__":
    main()
