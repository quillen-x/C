#!/usr/bin/env python3
"""Purge sex-category accounts with no posts in the last 180 days."""

from __future__ import annotations

import json
import sqlite3
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta
from pathlib import Path

SUPPORT = Path.home() / "Library/Application Support/com.xujiapeng.mediaDownloader"
DB_PATH = SUPPORT / "accounts.db"
SETTINGS_PATH = SUPPORT / "settings.json"
INACTIVE_DAYS = 180
WORKERS = 4
REQUEST_GAP = 0.08


def load_following() -> set[str]:
    with SETTINGS_PATH.open(encoding="utf-8") as handle:
        data = json.load(handle)
    return {str(item).strip().lower() for item in data.get("xFollowing") or [] if str(item).strip()}


def load_sex_accounts(following: set[str]) -> list[tuple[str, int]]:
    con = sqlite3.connect(DB_PATH)
    rows = con.execute(
        """
        SELECT username, COALESCE(last_post_at, 0)
        FROM accounts
        WHERE LOWER(TRIM(category)) = 'sex'
        ORDER BY username COLLATE NOCASE
        """
    ).fetchall()
    con.close()
    return [
        (str(username), int(last_post_at or 0))
        for username, last_post_at in rows
        if str(username).strip() and str(username).lower() in following
    ]


def fetch_latest_ms(username: str) -> tuple[str, int | None, str | None]:
    query = urllib.parse.urlencode({"count": "8", "lang": "zh-cn"})
    url = f"https://api.fxtwitter.com/2/profile/{urllib.parse.quote(username)}/statuses?{query}"
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        return username, None, f"http {error.code}"
    except Exception as error:  # noqa: BLE001
        return username, None, str(error)

    if (payload.get("code") or 0) != 200:
        return username, None, f"code {payload.get('code')}"

    results = payload.get("results") or []
    latest = 0
    for item in results:
        if not isinstance(item, dict):
            continue
        ts = item.get("created_timestamp")
        if isinstance(ts, (int, float)) and ts > 0:
            latest = max(latest, int(ts * 1000))
    if not results:
        return username, 0, None
    if latest <= 0:
        return username, None, "no timestamps"
    return username, latest, None


def main() -> None:
    cutoff = datetime.now() - timedelta(days=INACTIVE_DAYS)
    cutoff_ms = int(cutoff.timestamp() * 1000)
    following = load_following()
    accounts = load_sex_accounts(following)
    print(f"sex accounts in following: {len(accounts)}")
    print(f"cutoff: {cutoff.isoformat(sep=' ', timespec='seconds')}")

    to_purge: list[str] = []
    to_keep: list[str] = []
    failed: list[str] = []
    updated_last_post: dict[str, int] = {}
    need_api: list[str] = []

    for username, last_post_at in accounts:
        if last_post_at >= cutoff_ms:
            to_keep.append(username)
        elif last_post_at > 0:
            to_purge.append(username)
        else:
            need_api.append(username)

    print(f"already active from cache: {len(to_keep)}")
    print(f"inactive from cache: {len(to_purge)}")
    print(f"need api check: {len(need_api)}")

    done = 0
    total = len(need_api)
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {pool.submit(fetch_latest_ms, username): username for username in need_api}
        for future in as_completed(futures):
            username = futures[future]
            done += 1
            latest_ms, error = None, None
            try:
                username, latest_ms, error = future.result()
            except Exception as exc:  # noqa: BLE001
                error = str(exc)

            if error:
                failed.append(username)
            elif latest_ms is None:
                failed.append(username)
            elif latest_ms == 0:
                to_purge.append(username)
            elif latest_ms < cutoff_ms:
                to_purge.append(username)
                updated_last_post[username] = latest_ms
            else:
                to_keep.append(username)
                updated_last_post[username] = latest_ms

            if done % 50 == 0 or done == total:
                print(
                    f"progress {done}/{total} "
                    f"purge={len(to_purge)} keep={len(to_keep)} failed={len(failed)}"
                )
            time.sleep(REQUEST_GAP / WORKERS)

    purge_set = {name.lower() for name in to_purge}
    print(f"final purge: {len(purge_set)} failed: {len(failed)}")

    if not purge_set:
        print("nothing to purge")
        return

    con = sqlite3.connect(DB_PATH)
    try:
        con.execute("BEGIN")
        for username, millis in updated_last_post.items():
            con.execute(
                """
                UPDATE accounts
                SET last_post_at = MAX(COALESCE(last_post_at, 0), ?)
                WHERE username = ? COLLATE NOCASE
                """,
                (millis, username),
            )
        placeholders = ",".join("?" for _ in purge_set)
        con.execute(
            f"DELETE FROM accounts WHERE LOWER(username) IN ({placeholders})",
            list(purge_set),
        )
        con.commit()
    except Exception:
        con.rollback()
        raise
    finally:
        con.close()

    with SETTINGS_PATH.open(encoding="utf-8") as handle:
        settings = json.load(handle)
    following_list = settings.get("xFollowing") or []
    settings["xFollowing"] = [
        name for name in following_list if str(name).lower() not in purge_set
    ]
    with SETTINGS_PATH.open("w", encoding="utf-8") as handle:
        json.dump(settings, handle, ensure_ascii=False, indent=2)

    print(f"removed from following: {len(following_list) - len(settings['xFollowing'])}")
    print("done")


if __name__ == "__main__":
    main()
