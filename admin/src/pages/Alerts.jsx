import { useEffect, useState, useCallback } from 'react'
import { AlertTriangle, CheckCircle, ChevronLeft, ChevronRight, Calendar, Info, ExternalLink, EyeOff, Eye } from 'lucide-react'
import api from '../api'

// 2026-05-29 P0 #3 — Codex 사전 Q3: 보수적 라벨. "반영됨"은 실제 price write 확인된 상태에만 사용.
// 시세 모델 freeze (project_chase_pricing_model_status) 와 충돌 위험 차단.
const PRICE_REFLECT_MAP = {
  CONTAMINATION_CONFIRMED: { label: '제외 처리됨', color: '#15803d', bg: '#f0fdf4', border: '#bbf7d0' },
  PRICE_DROP_ACCEPTED:     { label: '가격 하락 허용', color: '#1d4ed8', bg: '#eff6ff', border: '#bfdbfe' },
  NO_DATA:                 { label: '판정 보류',     color: '#64748b', bg: '#f8fafc', border: '#e2e8f0' },
  NO_COL_NUM:              { label: '판정 보류',     color: '#64748b', bg: '#f8fafc', border: '#e2e8f0' },
  EBAY_ERROR:              { label: '판정 보류',     color: '#64748b', bg: '#f8fafc', border: '#e2e8f0' },
  SKIPPED:                 { label: '판정 보류',     color: '#64748b', bg: '#f8fafc', border: '#e2e8f0' },
}
function reflectLabel(ebayResult) {
  return PRICE_REFLECT_MAP[ebayResult] ?? { label: '판정 보류', color: '#64748b', bg: '#f8fafc', border: '#e2e8f0' }
}

/** suspect 와 hist_median 으로 차이율 계산. null/0 safe. */
function diffPct(suspect, median) {
  if (suspect == null || median == null) return null
  const s = Number(suspect), m = Number(median)
  if (!Number.isFinite(s) || !Number.isFinite(m) || m === 0) return null
  return ((s - m) / m) * 100
}

/** scrydex 원본 url 조립. source + ref → 외부 링크. */
function scrydexUrl(source, enRef, jpRef) {
  if (source === 'SCRYDEX_EN' && enRef) return `https://scrydex.com/pokemon/cards/_/${enRef}`
  if (source === 'SCRYDEX_JP' && jpRef) return `https://scrydex.com/pokemon/cards/_/${jpRef}`
  return null
}

const S = {
  page:   { padding: '32px 36px', minHeight: '100%', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' },
  header: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 },
  h1:     { fontSize: 22, fontWeight: 700, color: '#1e293b', letterSpacing: -0.5 },
  sub:    { fontSize: 13, color: '#94a3b8', marginTop: 3 },
  card:   { background: '#fff', borderRadius: 16, border: '1px solid #e8edf4', boxShadow: '0 1px 3px rgba(0,0,0,0.04)', overflow: 'hidden' },
  th:     { padding: '12px 16px', fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.6, textAlign: 'left', background: '#f8fafc', borderBottom: '1px solid #f1f5f9' },
  td:     { padding: '13px 16px', fontSize: 13, color: '#475569', borderBottom: '1px solid #f8fafc', verticalAlign: 'middle' },
}

// eBay 검증 결과: 스크래퍼가 anomaly 감지 후 eBay에서 자동 교차검증한 결과
const EBAY_LABELS = {
  CONTAMINATION_CONFIRMED: { label: '오염 확인됨',    color: '#dc2626', bg: '#fef2f2', border: '#fecaca' },
  PRICE_DROP_ACCEPTED:     { label: 'eBay 정상 하락', color: '#16a34a', bg: '#f0fdf4', border: '#bbf7d0' },
  NO_DATA:                 { label: 'eBay 데이터 없음', color: '#94a3b8', bg: '#f8fafc', border: '#e2e8f0' },
  NO_COL_NUM:              { label: '번호 없음',       color: '#94a3b8', bg: '#f8fafc', border: '#e2e8f0' },
  EBAY_ERROR:              { label: 'eBay 오류',      color: '#d97706', bg: '#fffbeb', border: '#fde68a' },
  SKIPPED:                 { label: 'eBay 미검증',    color: '#7c3aed', bg: '#fdf4ff', border: '#e9d5ff' },
}

// 처리 방법 설명 (isResolved=true일 때)
function resolveExplanation(ebayResult) {
  switch (ebayResult) {
    case 'PRICE_DROP_ACCEPTED':     return 'eBay 교차검증 결과 정상 하락으로 확인 → 관리자가 처리 완료로 표시'
    case 'CONTAMINATION_CONFIRMED': return 'eBay에서 오염 데이터 확인 → scrydex 이상값 제외됨'
    case 'NO_DATA':
    case 'NO_COL_NUM':
    case 'EBAY_ERROR':              return 'eBay 미검증 상태에서 관리자가 직접 처리 완료로 표시'
    case 'SKIPPED':                 return 'eBay 검증 스킵 → 관리자가 처리 완료로 표시'
    default:                        return '관리자 처리 완료'
  }
}

function EbayBadge({ result }) {
  const s = EBAY_LABELS[result] ?? { label: result ?? '-', color: '#94a3b8', bg: '#f8fafc', border: '#e2e8f0' }
  return (
    <span style={{
      fontSize: 11, fontWeight: 700, padding: '3px 8px', borderRadius: 99,
      background: s.bg, color: s.color, border: `1px solid ${s.border}`,
    }}>{s.label}</span>
  )
}

function fmt(dt) {
  if (!dt) return '-'
  return new Date(dt).toLocaleString('ko-KR', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })
}

function fmtFull(dt) {
  if (!dt) return '-'
  return new Date(dt).toLocaleString('ko-KR', { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })
}

export default function Alerts() {
  const [items, setItems]         = useState([])
  const [total, setTotal]         = useState(0)
  const [page, setPage]           = useState(0)
  const [loading, setLoading]     = useState(true)
  const [showResolved, setShowResolved] = useState(false)
  const [resolving, setResolving] = useState(null)
  const [tooltip, setTooltip]     = useState(null)   // anomalyId of expanded row

  // 날짜 필터
  const [dates, setDates]         = useState([])       // [{date, total, unresolved}]
  const [selectedDate, setSelectedDate] = useState('') // '' = 전체

  const size = 30

  // 날짜 목록 로드
  useEffect(() => {
    api.get('/admin/price-anomaly-dates')
      .then(r => setDates(r.data?.data ?? []))
      .catch(() => {})
  }, [])

  const load = useCallback(() => {
    setLoading(true)
    const params = { resolved: showResolved, page, size }
    if (selectedDate) params.date = selectedDate
    api.get('/admin/price-anomalies', { params })
      .then(r => {
        setItems(r.data?.data?.content ?? [])
        setTotal(r.data?.data?.totalElements ?? 0)
      })
      .catch(() => { setItems([]); setTotal(0) })
      .finally(() => setLoading(false))
  }, [page, showResolved, selectedDate])

  useEffect(() => { load() }, [load])

  // 2026-05-29 P0 #3 — action 분기 (REVIEWED|DISMISSED). DISMISSED 는 사유 prompt 권장.
  const resolveWithAction = async (anomalyId, action) => {
    let memo = null
    if (action === 'DISMISSED') {
      memo = prompt('무시 사유 (audit 기록용):')
      if (memo === null) return  // cancel
      if (!memo.trim()) { alert('사유를 입력하세요'); return }
    }
    setResolving(anomalyId)
    try {
      await api.post(`/admin/price-anomalies/${anomalyId}/resolve`, { action, memo })
      load()
    } catch (e) {
      alert(e.response?.data?.message ?? '처리 실패')
    } finally {
      setResolving(null)
    }
  }

  const totalPages = Math.ceil(total / size)
  const unresolvedTotal = dates.reduce((s, d) => s + d.unresolved, 0)

  return (
    <div style={S.page}>
      <div style={S.header}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <AlertTriangle size={20} color="#dc2626" />
            <span style={S.h1}>가격 이상 알림</span>
            {unresolvedTotal > 0 && (
              <span style={{
                fontSize: 12, fontWeight: 700, padding: '3px 10px', borderRadius: 99,
                background: '#fef2f2', color: '#dc2626', border: '1px solid #fecaca',
              }}>{unresolvedTotal.toLocaleString()}건 미처리</span>
            )}
          </div>
          <div style={S.sub}>
            스크래퍼가 감지한 이상 가격 · eBay 교차검증 자동 실행 · 관리자 최종 확인 필요
          </div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button onClick={() => { setShowResolved(v => !v); setPage(0) }} style={{
            padding: '8px 16px', borderRadius: 10, border: '1px solid #e2e8f0',
            background: showResolved ? '#6366f1' : '#fff',
            color: showResolved ? '#fff' : '#64748b',
            fontSize: 13, fontWeight: 600, cursor: 'pointer', fontFamily: 'inherit',
          }}>
            {showResolved ? '미처리만 보기' : '처리 완료 포함'}
          </button>
        </div>
      </div>

      {/* 날짜 필터 */}
      {dates.length > 0 && (
        <div style={{ display: 'flex', gap: 8, marginBottom: 16, flexWrap: 'wrap', alignItems: 'center' }}>
          <Calendar size={14} color="#94a3b8" />
          <span style={{ fontSize: 12, color: '#94a3b8', fontWeight: 600 }}>날짜 필터:</span>
          <button
            onClick={() => { setSelectedDate(''); setPage(0) }}
            style={{
              padding: '5px 12px', borderRadius: 8, border: '1px solid #e2e8f0', cursor: 'pointer',
              background: selectedDate === '' ? '#6366f1' : '#fff',
              color: selectedDate === '' ? '#fff' : '#475569',
              fontSize: 12, fontWeight: 600, fontFamily: 'inherit',
            }}
          >전체</button>
          {dates.map(d => (
            <button
              key={d.date}
              onClick={() => { setSelectedDate(d.date); setPage(0) }}
              style={{
                padding: '5px 12px', borderRadius: 8, border: '1px solid #e2e8f0', cursor: 'pointer',
                background: selectedDate === d.date ? '#6366f1' : '#fff',
                color: selectedDate === d.date ? '#fff' : '#475569',
                fontSize: 12, fontWeight: 600, fontFamily: 'inherit',
                position: 'relative',
              }}
            >
              {d.date.slice(5)}
              {d.unresolved > 0 && (
                <span style={{
                  marginLeft: 5, fontSize: 10, fontWeight: 800,
                  color: selectedDate === d.date ? '#fde68a' : '#dc2626',
                }}>{d.unresolved}</span>
              )}
            </button>
          ))}
        </div>
      )}

      {/* 처리 방법 안내 */}
      <div style={{
        display: 'flex', gap: 8, alignItems: 'flex-start', padding: '12px 16px', borderRadius: 12,
        background: '#f8fafc', border: '1px solid #e8edf4', marginBottom: 16, fontSize: 12, color: '#64748b',
      }}>
        <Info size={14} color="#94a3b8" style={{ flexShrink: 0, marginTop: 1 }} />
        <div style={{ lineHeight: 1.8 }}>
          <b style={{ color: '#475569' }}>이상 감지 → eBay 교차검증 → 알림 닫기</b><br />
          스크래퍼가 PSA 등급역전/급락을 감지하면 eBay에서 실제 거래가를 자동 비교합니다.
          버튼을 눌러 해당 알림을 미처리 목록에서 제거합니다 (DB 데이터에는 영향 없음).<br />
          <span style={{ color: '#15803d', fontWeight: 600 }}>● eBay 정상 하락</span> — eBay에서도 같은 가격대 확인됨, 실제 하락이 맞음{' '}
          <span style={{ marginLeft: 12, color: '#b91c1c', fontWeight: 600 }}>● 오염 확인됨</span> — scrydex 이상값, 해당 데이터 이미 시세 계산에서 제외됨
        </div>
      </div>

      <div style={S.card}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              {['카드명', '소스', '감지 시각', '이상 내용', 'Suspect (USD)', '기존 중앙값', 'eBay 교차검증', '처리 상태'].map(h => (
                <th key={h} style={S.th}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={8} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: 40 }}>불러오는 중...</td></tr>
            ) : items.length === 0 ? (
              <tr>
                <td colSpan={8} style={{ ...S.td, textAlign: 'center', padding: 48 }}>
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
                    <CheckCircle size={32} color="#22c55e" />
                    <span style={{ color: '#64748b', fontSize: 14 }}>이상 없음 — 모든 가격이 정상 범위입니다</span>
                  </div>
                </td>
              </tr>
            ) : items.map(a => (
              <>
                <tr key={a.anomalyId}
                  onClick={() => setTooltip(tooltip === a.anomalyId ? null : a.anomalyId)}
                  style={{ cursor: 'pointer' }}
                  onMouseEnter={e => e.currentTarget.style.background = '#fafafa'}
                  onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
                >
                  <td style={{ ...S.td, fontWeight: 600, color: '#1e293b' }}>
                    <div>{a.cardName ?? '-'}</div>
                    <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 2 }}>{a.cardId}</div>
                  </td>
                  <td style={S.td}>
                    <span style={{
                      fontSize: 11, fontWeight: 700, padding: '3px 8px', borderRadius: 99,
                      background: a.source === 'SCRYDEX_JP' ? '#eff6ff' : '#f0fdf4',
                      color: a.source === 'SCRYDEX_JP' ? '#1d4ed8' : '#15803d',
                      border: `1px solid ${a.source === 'SCRYDEX_JP' ? '#bfdbfe' : '#bbf7d0'}`,
                    }}>{a.source}</span>
                  </td>
                  <td style={{ ...S.td, fontSize: 12, color: '#94a3b8', whiteSpace: 'nowrap' }}>{fmt(a.detectedAt)}</td>
                  <td style={{ ...S.td, fontSize: 12, maxWidth: 260 }}>
                    <span title={a.reason} style={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {a.reason ?? '-'}
                    </span>
                  </td>
                  <td style={{ ...S.td, fontWeight: 600, color: '#dc2626' }}>
                    {a.suspectPriceUsd ? `$${Number(a.suspectPriceUsd).toLocaleString()}` : '-'}
                  </td>
                  <td style={{ ...S.td, color: '#64748b' }}>
                    {a.histMedianUsd ? `$${Number(a.histMedianUsd).toLocaleString()}` : '-'}
                  </td>
                  <td style={S.td}><EbayBadge result={a.ebayResult} /></td>
                  <td style={S.td}>
                    {a.isResolved ? (
                      <div>
                        <span style={{
                          fontSize: 11, fontWeight: 700, padding: '3px 8px', borderRadius: 99,
                          background: a.resolutionType === 'DISMISSED' ? '#fef2f2' : '#f0fdf4',
                          color: a.resolutionType === 'DISMISSED' ? '#b91c1c' : '#16a34a',
                          border: `1px solid ${a.resolutionType === 'DISMISSED' ? '#fecaca' : '#bbf7d0'}`,
                          display: 'inline-flex', alignItems: 'center', gap: 4,
                        }}>
                          {a.resolutionType === 'DISMISSED'
                            ? <><EyeOff size={11} /> 무시됨</>
                            : <><CheckCircle size={11} /> 검토 완료</>}
                        </span>
                        <div style={{ fontSize: 10, color: '#94a3b8', marginTop: 3 }}>
                          {a.resolvedAt ? fmtFull(a.resolvedAt) : '-'}
                        </div>
                      </div>
                    ) : (
                      // 2026-05-29 P0 #3: 4 버튼 — 카드 상세 / 원본 보기 / 검토 완료 / 무시.
                      // Codex 사전 Q4: REVIEWED vs DISMISSED 구분 → resolution_type 컬럼 저장.
                      (() => {
                        const src = scrydexUrl(a.source, a.enScrydexRef, a.jpScrydexRef)
                        const busy = resolving === a.anomalyId
                        const Btn = ({ onClick, color, border, text, label, disabled, icon }) => (
                          <button
                            onClick={onClick}
                            disabled={disabled || busy}
                            style={{
                              padding: '4px 8px', borderRadius: 6,
                              border: `1px solid ${border}`,
                              background: disabled ? '#f8fafc' : color,
                              color: disabled ? '#cbd5e1' : text,
                              fontSize: 11, fontWeight: 600,
                              cursor: disabled || busy ? 'not-allowed' : 'pointer',
                              fontFamily: 'inherit', whiteSpace: 'nowrap',
                              display: 'inline-flex', alignItems: 'center', gap: 3,
                            }}
                          >{icon}{label}</button>
                        )
                        return (
                          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 4, minWidth: 200 }}>
                            <Btn
                              onClick={e => { e.stopPropagation(); window.open(`/admin/cards?search=${encodeURIComponent(a.cardName ?? a.cardId)}`, '_blank') }}
                              color="#fff" border="#cbd5e1" text="#475569"
                              icon={<Eye size={10} />} label="카드 상세"
                            />
                            <Btn
                              onClick={e => { e.stopPropagation(); if (src) window.open(src, '_blank') }}
                              disabled={!src}
                              color="#fff" border="#cbd5e1" text="#475569"
                              icon={<ExternalLink size={10} />} label={src ? '원본 보기' : '원본 X'}
                            />
                            <Btn
                              onClick={e => { e.stopPropagation(); resolveWithAction(a.anomalyId, 'REVIEWED') }}
                              color="#f0fdf4" border="#86efac" text="#15803d"
                              icon={<CheckCircle size={10} />} label="검토 완료"
                            />
                            <Btn
                              onClick={e => { e.stopPropagation(); resolveWithAction(a.anomalyId, 'DISMISSED') }}
                              color="#fef2f2" border="#fca5a5" text="#b91c1c"
                              icon={<EyeOff size={10} />} label="무시"
                            />
                          </div>
                        )
                      })()
                    )}
                  </td>
                </tr>
                {/* 행 클릭 시 처리 방법 상세 표시 */}
                {tooltip === a.anomalyId && (() => {
                  // 2026-05-29 P0 #3: 운영자가 행동 결정 가능하도록 정보 강화.
                  //   - 이상 유형 / 원천 / 차이율 / 앱 시세 반영 여부 / 권장 조치
                  const diff = diffPct(a.suspectPriceUsd, a.histMedianUsd)
                  const reflect = reflectLabel(a.ebayResult)
                  return (
                  <tr key={`${a.anomalyId}-detail`}>
                    <td colSpan={8} style={{ padding: '0 16px 12px', background: '#f8fafc', borderBottom: '1px solid #f1f5f9' }}>
                      <div style={{ padding: '12px 16px', borderRadius: 10, background: '#fff', border: '1px solid #e2e8f0', fontSize: 12, color: '#374151', lineHeight: 1.8 }}>
                        <div style={{ fontWeight: 700, color: '#1e293b', marginBottom: 6 }}>처리 흐름 · 운영 판단 정보</div>
                        <div style={{ display: 'grid', gridTemplateColumns: 'auto 1fr', gap: '2px 12px' }}>
                          <span style={{ color: '#94a3b8', fontWeight: 600 }}>감지 시각</span>
                          <span>{fmtFull(a.detectedAt)}</span>

                          <span style={{ color: '#94a3b8', fontWeight: 600 }}>이상 유형</span>
                          <span><EbayBadge result={a.ebayResult} /><span style={{ marginLeft: 8, color: '#475569' }}>{EBAY_LABELS[a.ebayResult]?.label ?? a.ebayResult}</span></span>

                          <span style={{ color: '#94a3b8', fontWeight: 600 }}>원천 데이터</span>
                          <span style={{ color: '#475569', fontWeight: 600 }}>{a.source} {a.cardId}</span>

                          <span style={{ color: '#94a3b8', fontWeight: 600 }}>이상 내용</span>
                          <span>{a.reason ?? '-'}</span>

                          <span style={{ color: '#94a3b8', fontWeight: 600 }}>기준값 대비 차이율</span>
                          <span style={{ color: diff != null && diff < 0 ? '#dc2626' : diff != null && diff > 0 ? '#16a34a' : '#94a3b8', fontWeight: 700 }}>
                            {diff != null
                              ? `${diff > 0 ? '+' : ''}${diff.toFixed(1)}% (suspect $${a.suspectPriceUsd} vs 중앙값 $${a.histMedianUsd})`
                              : '계산 불가 (중앙값 없음)'}
                          </span>

                          <span style={{ color: '#94a3b8', fontWeight: 600 }}>앱 시세 반영 여부</span>
                          <span>
                            <span style={{
                              fontSize: 11, fontWeight: 700, padding: '2px 8px', borderRadius: 99,
                              background: reflect.bg, color: reflect.color, border: `1px solid ${reflect.border}`,
                            }}>{reflect.label}</span>
                          </span>

                          {a.isResolved ? (
                            <>
                              <span style={{ color: '#94a3b8', fontWeight: 600 }}>처리 완료</span>
                              <span>
                                {fmtFull(a.resolvedAt)} ·{' '}
                                <b style={{ color: a.resolutionType === 'DISMISSED' ? '#b91c1c' : '#15803d' }}>
                                  {a.resolutionType === 'DISMISSED' ? '무시됨' : '검토 완료'}
                                </b>
                              </span>
                            </>
                          ) : (
                            <>
                              <span style={{ color: '#94a3b8', fontWeight: 600 }}>권장 조치</span>
                              <span style={{ color: '#b45309', fontWeight: 600 }}>
                                {a.ebayResult === 'CONTAMINATION_CONFIRMED'
                                  ? '오염 데이터 확인됨 — 이미 시세 계산에서 제외. "검토 완료" 추천'
                                  : a.ebayResult === 'PRICE_DROP_ACCEPTED'
                                    ? 'eBay 정상 하락 확인됨 — 본인 판단으로 "검토 완료" 또는 "무시"'
                                    : '판정 보류 상태 — 운영자 직접 확인 후 처리'}
                              </span>
                            </>
                          )}
                        </div>
                      </div>
                    </td>
                  </tr>
                  )
                })()}
              </>
            ))}
          </tbody>
        </table>

        {totalPages > 1 && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 8, padding: '12px 16px', borderTop: '1px solid #f1f5f9' }}>
            <span style={{ fontSize: 12, color: '#94a3b8', marginRight: 8 }}>총 {total.toLocaleString()}건</span>
            <button onClick={() => setPage(p => Math.max(0, p - 1))} disabled={page === 0}
              style={{ padding: 5, border: '1px solid #e2e8f0', borderRadius: 8, background: '#fff', cursor: page === 0 ? 'not-allowed' : 'pointer', opacity: page === 0 ? 0.4 : 1 }}>
              <ChevronLeft size={15} color="#64748b" />
            </button>
            <span style={{ fontSize: 13, color: '#64748b' }}>{page + 1} / {totalPages}</span>
            <button onClick={() => setPage(p => Math.min(totalPages - 1, p + 1))} disabled={page >= totalPages - 1}
              style={{ padding: 5, border: '1px solid #e2e8f0', borderRadius: 8, background: '#fff', cursor: page >= totalPages - 1 ? 'not-allowed' : 'pointer', opacity: page >= totalPages - 1 ? 0.4 : 1 }}>
              <ChevronRight size={15} color="#64748b" />
            </button>
          </div>
        )}
      </div>
    </div>
  )
}
