// 공용 토글 스위치 — 접근성(role=switch + aria) + 키보드(Enter/Space) + loading/disabled 중복클릭 차단.
//   controlled: checked(서버 확정값) + onChange(next). ★loading 중에도 checked 그대로 렌더(전환 결과를 미리 뒤집어 보이지 않음
//   — 낙관적 표시는 부모 책임). 기존 Admin 토큰만(active #4f46e5 / inactive #cbd5e1). 새 전역 CSS 없음(spin = index.css 재사용).
export default function ToggleSwitch({ checked = false, onChange, disabled = false, loading = false, ariaLabel, id }) {
  const blocked = disabled || loading

  function activate() {
    if (blocked) return // 처리 중·비활성 시 중복 클릭/키 입력 무시
    onChange?.(!checked)
  }

  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-busy={loading || undefined}
      aria-label={ariaLabel}
      aria-disabled={blocked || undefined}
      id={id}
      disabled={blocked}
      onClick={activate}
      style={{
        position: 'relative', width: 40, height: 22, flexShrink: 0,
        border: 'none', borderRadius: 999, padding: 0,
        background: checked ? '#4f46e5' : '#cbd5e1', // loading 중에도 checked(현재 확정값) 유지
        cursor: blocked ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.5 : 1,
        transition: 'background 0.15s',
        verticalAlign: 'middle',
      }}
    >
      <span
        aria-hidden="true"
        style={{
          position: 'absolute', top: 2, left: checked ? 20 : 2,
          width: 18, height: 18, borderRadius: '50%', background: '#fff',
          boxShadow: '0 1px 2px rgba(0,0,0,0.25)', transition: 'left 0.15s',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}
      >
        {loading && (
          <span style={{
            width: 10, height: 10, borderRadius: '50%',
            border: '2px solid #c7d2fe', borderTopColor: '#4f46e5',
            animation: 'spin 0.6s linear infinite',
          }} />
        )}
      </span>
    </button>
  )
}
