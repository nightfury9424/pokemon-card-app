-- 학습 소요시간 가시화 (admin) — 학습 시작 시각. 경과(now-started) + 지난번 소요(trained-started) 계산용.
ALTER TABLE scan_train_jobs ADD COLUMN training_started_at TIMESTAMP;
