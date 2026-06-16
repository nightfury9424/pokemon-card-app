# P3 + P5 패치 보관 (2026-06-16) — P3 HOLD

> 로컬 GlobalPriceService.java에 적용했다가 **dry-run 결과 P3 단독배포 위험 발견 → 로컬 되돌림(local==prod 복원).**
> 아래는 재적용용 보관. **P3는 P2(계수 재보정)와 함께만 배포.** P5는 단독 가능하나 현재 보류.
> 파일: `back/src/main/java/com/fury/back/domain/price/GlobalPriceService.java`

## P5 — 부분실패 가드 (단독 배포 안전, 시세 변화 0) ✅ ready
6/15 사고: 후보 ~3700장인데 build 결과 4장만 → 그대로 저장돼 catalog가 6/14값으로 묶임("완료" silent). 원인 메커니즘 = buildKo line 890 `if (koPrice <= 0) continue;` (계수/FX가 0이면 카드 silent 드롭. 6/15엔 cold cache/recalc실패 추정).

`refreshKoEstimatesFromSnapshots()` 의 count-mismatch 검증 직후, `if (!koSnapshots.isEmpty())` 를 아래로 교체:
```java
            // P5 가드 (2026-06-16): 후보(allIds)는 충분한데 build 결과가 비정상적으로 적으면 부분실패로 보고
            // KO_ESTIMATED delete/save 중단(기존 live 보존). delete 전에 abort.
            boolean partialFailure = allIds.size() >= 1000 && koSnapshots.size() < allIds.size() * 0.5;
            if (partialFailure) {
                log.error("[KoEstimated] ★ABORT 부분실패 감지: allIds={} snapshots={} ({}%) "
                                + "-> delete/save 중단, 기존 KO_ESTIMATED 보존. enSource={} jpSource={}",
                        allIds.size(), koSnapshots.size(),
                        Math.round(koSnapshots.size() * 100.0 / Math.max(allIds.size(), 1)),
                        enSnapshots.size(), jpSnapshots.size());
            } else if (!koSnapshots.isEmpty()) {
```
(Codex GO·로컬 컴파일 통과. abort 알람 미연결 — log.error만, 모니터링 후속.)

## P3 — spread가드 JP-first (★HOLD — P2 없이 배포 금지)
`selectScrydexSnapshotForKo()` 의 spread 초과 블록에서 `return enSnapshot;` 제거(JP 유지, 경고만).
```java
                if (low > 0 && high / low > threshold) {
                    // P3 (2026-06-16): JP-first — JP 있으면 spread 커도 EN으로 뒤집지 않음(경고만).
                    log.warn("[KO-GUARD] cardId={} rarity={} jp={} en={} -> spread={} > threshold={} (prevSource={}), JP 유지 (EN flip 제거)",
                            cardId, rarity, Math.round(jpKrw), Math.round(enKrw),
                            Math.round((high / low) * 10.0) / 10.0, threshold, prevSource);
                }
```
**★HOLD 이유 (dry-run 2026-06-16):** isJpRawSuspect(JP/EN>8·cap) 적용해도 **~315장 UP, 일부 폭등**(피카츄 EX SR 82,194→884,471). 원인 = P3가 JP를 고르면 `jp × 과대 rarity계수(SR≈0.8)`로 폭등. **spread가드가 우연히 이 폭등을 막고 있었음.** → **P2(계수 0.16대 재보정) 완료 후 P3+P2 같이 배포해야 안전.** isJpRawSuspect(corrupt JP)는 P3에서도 보존됨.

## 재적용 순서 (P2 준비 후)
1. P2 계수 재보정(recalc 정제) 먼저
2. P3+P5 재적용 → Codex 사후리뷰 → 컴파일 → 점검토글 → rebuild/redeploy → health report before/after → 캐시(재배포로 자동 클리어)
