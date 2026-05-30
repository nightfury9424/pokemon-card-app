# 운영 cron scripts

prod 의 `/opt/pokefolio/cron/` 와 동기화되는 영구 사본. 새 환경 셋업 시 이 디렉토리 사본을 prod 의 같은 위치에 복사 + chmod +x.

## 매일 운영 cron (KST)

| 시각 | 스크립트 | 역할 |
|---|---|---|
| 23:50 | `hold_outliers_daily.sh` | SCRYDEX outlier 카드 (통화 parse 버그 / eBay scrape mismatch) 어제값 carry |
| 23:52 | `v6_apply_daily.sh` | v6 시세 모델 — chase floor / EN→JP 브릿지 / MANUAL_FLOOR 보정 |
| 23:55 | `sanity_cap_extreme_daily.sh` | 극단치 cap (RATIO/DAANGN/HIT 등) |

## 23:45 Spring Scheduler (cron 아님, Java @Scheduled)

`back/src/main/java/com/fury/back/domain/price/PriceSyncScheduler.java`
- `refreshKoEstimates()` — KO_ESTIMATED 단순 산식 (audit + price_snapshots 재생성)
- 23:52 v6_apply 가 그 결과를 chase 보정 overlay

## 호스트 crontab

```
50 23 * * * /opt/pokefolio/cron/hold_outliers_daily.sh
52 23 * * * /opt/pokefolio/cron/v6_apply_daily.sh
55 23 * * * /opt/pokefolio/cron/sanity_cap_extreme_daily.sh
```

## 변경 이력

- **2026-05-31 hold_outliers v2** — 14 hardcoded count → 동적 count + is_visible/today snapshot 가드 + 두빅굴 EX RR / 차곡차곡 GX SR 추가 (scrydex eBay scrape mismatch hold).
- 2026-05-26 v1 — 14 카드 hardcoded (SCRYDEX JP currency parse 버그).

## 주의

- 이 cron 들은 **운영 시세 freeze 정책의 일부** — [[project-chase-pricing-model-status]] 참조.
- `refresh-ko-estimates` 같은 admin endpoint 수동 호출은 cron 흐름을 깨뜨림 (2026-05-30 사고 사례) — `DangerousAdminFilter` 로 차단.
