-- 중복 신고 방지(같은 신고자가 같은 대상 사용자를 1회만) — 사전 dedup(ReportController existsBy...) 의
-- TOCTOU 경쟁까지 DB 레벨로 차단. board 는 block unique 가 이미 커버하나, 사용자가 대상을 사전 차단한 상태면
-- block insert 가 생략돼 경쟁 시 중복 신고가 통과할 수 있어 reports 자체 제약이 필요.
--
-- ★★ RC 배포 게이트 — prod 적용 전 필수(지금 실행 금지):
--   (1) pg_dump 백업.
--   (2) 기존 중복 row 점검(0건이어야 적용 가능). 1건↑ 이면 정책에 맞게 정리 후 적용:
--         SELECT reporter_id, target_user_id, COUNT(*) AS n
--         FROM reports WHERE target_user_id IS NOT NULL
--         GROUP BY reporter_id, target_user_id HAVING COUNT(*) > 1;
--   (3) 적용 후 애플리케이션: reportRepository.saveAndFlush(report) 의 unique 위반을
--       "이미 신고하신 항목" 으로 매핑(제약명 확인 or 사전체크). 현재는 미적용이라 미반영 — 적용과 함께 추가.
--
-- target_user_id IS NULL(BUY_ORDER 등 대상 사용자 미해석)은 제약 대상 아님 → 부분 인덱스.
-- 정책: existsByReporterIdAndTargetUserId (status 무관, '차단 풀고 재신고 방지') 와 동일 의미.
CREATE UNIQUE INDEX IF NOT EXISTS uq_reports_reporter_target
    ON reports (reporter_id, target_user_id)
    WHERE target_user_id IS NOT NULL;
