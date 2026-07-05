// 확률 계산기 수학 — 순수 함수 (node로 단독 테스트 가능하게 분리)

/** 평균 출현율 모델 — 이항 독립시행 근사 (팩 무작위 혼합/자판기 가정). P(X>=1 in n packs) */
export const binomAtLeastOne = (p, n) => {
  if (!(p > 0) || !(n > 0)) return 0
  return 1 - Math.pow(1 - Math.min(1, p), n)
}

/**
 * 카톤 고정 봉입 모델 — 같은 sealed 카톤 내 비복원 추출 (초기하).
 * P(X>=1) = 1 - C(N-K, n)/C(N, n) = 1 - ∏_{i=0}^{n-1} (N-K-i)/(N-i)
 * N=카톤 전체 팩 수, K=카톤 내 봉입 수(정수), n=개봉 팩 수. n > N-K 이면 확정(1).
 */
export const hyperAtLeastOne = (N, K, n) => {
  if (!(K >= 1) || !(n > 0) || !(N > 0)) return 0
  const k = Math.min(Math.floor(K), N)
  const draws = Math.min(Math.floor(n), N)
  if (draws > N - k) return 1
  let miss = 1
  for (let i = 0; i < draws; i++) miss *= (N - k - i) / (N - i)
  return 1 - miss
}

/** 고정 봉입 — 첫 히트까지 평균 개봉 팩 수 (순차 비복원): (N+1)/(K+1) */
export const hyperExpectedPacksToFirst = (N, K) => {
  if (!(K >= 1) || !(N > 0)) return Infinity
  return (N + 1) / (Math.min(Math.floor(K), N) + 1)
}
