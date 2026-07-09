#!/usr/bin/env python3
"""SNK sales-chart / detail fetch. snk_price_pull_full.py 의 로직 재사용.

429/403 즉시 중단·재개가능. points = [ts_ms, price_jpy]. all(-1) 미수집.
read-only 외부 공개 API — prod DB 무관.
"""
import json
import statistics
import time
import urllib.error
import urllib.request

from . import config


class SnkBlocked(Exception):
    """403/429 — 즉시 중단 신호."""


def fetch(url: str, retry: int = 1):
    for i in range(retry + 1):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "Mozilla/5.0", "Accept": "application/json"})
            return json.load(urllib.request.urlopen(req, timeout=12))
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(3)
                continue
            if e.code == 403:
                raise SnkBlocked(f"403 on {url}")
            return None
        except Exception:
            if i < retry:
                time.sleep(0.5)
                continue
            return None
    return None


def _pts(d):
    if not d:
        return []
    return [p[1] for p in (d.get("points") or [])
            if isinstance(p, list) and len(p) >= 2 and p[1]]


def median(xs):
    return int(statistics.median(xs)) if xs else 0


def latest(xs):
    return xs[-1] if xs else 0


def chart(apparel_id, range_param: str, opt: int):
    """range_param: 'oneMonth' | 'threeMonths'. returns list[price_jpy]."""
    url = config.SNK_BASE.format(apparel_id) + \
        f"/sales-chart/used?range={range_param}&salesChartOptionId={opt}"
    return _pts(fetch(url))


def chart_pairs(apparel_id, range_param: str, opt: int):
    """검수 차트용: [(ts_ms, price_jpy), ...] ts 보존."""
    url = config.SNK_BASE.format(apparel_id) + \
        f"/sales-chart/used?range={range_param}&salesChartOptionId={opt}"
    d = fetch(url)
    if not d:
        return []
    out = []
    for p in (d.get("points") or []):
        if isinstance(p, list) and len(p) >= 2 and p[1]:
            try:
                out.append((int(p[0]), int(p[1])))
            except (TypeError, ValueError):
                pass
    return out


def detail(apparel_id):
    """usedMinPrice (ASK 보조), usedListingCount."""
    return fetch(config.SNK_BASE.format(apparel_id)) or {}
