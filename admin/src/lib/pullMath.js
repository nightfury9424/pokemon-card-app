// 확률 계산기 수학 — 순수 함수 (node 단독 테스트 가능하게 분리)

/** 독립 시행 n회 중 최소 1회 성공 — P(X>=1) = 1-(1-p)^n. 박스 단위(박스끼리 독립 밀봉) 가정. */
export const atLeastOne = (p, n) => {
  if (!(p > 0) || !(n > 0)) return 0
  return 1 - Math.pow(1 - Math.min(1, p), n)
}

/** 두 독립 경로 중 하나 이상 성공 — P(A∪B) = 1-(1-a)(1-b). 단순 합산(a+b) 대신 사용해 이중계산 방지. */
export const unionIndependent = (a, b) => {
  const pa = a > 0 ? Math.min(1, a) : 0
  const pb = b > 0 ? Math.min(1, b) : 0
  return 1 - (1 - pa) * (1 - pb)
}

/** 목표 누적확률(target) 도달에 필요한 시행 수(올림) — n s.t. 1-(1-p)^n >= target */
export const trialsToReach = (p, target) => {
  if (!(p > 0) || !(target > 0)) return Infinity
  if (p >= 1) return 1
  if (target >= 1) return Infinity
  return Math.ceil(Math.log(1 - target) / Math.log(1 - p))
}
