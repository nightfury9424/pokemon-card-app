import { useEffect, useState } from 'react'
import { RefreshCw, TrendingUp, Search, CheckCircle, XCircle, Zap, Database, Activity } from 'lucide-react'
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts'
import api from '../api'

const S = {
  page:  { padding: '28px 32px', minHeight: '100%', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' },
  card:  { background: '#fff', borderRadius: 16, border: '1px solid #e8edf4', boxShadow: '0 1px 4px rgba(0,0,0,0.05)' },
  h2:    { fontSize: 15, fontWeight: 700, color: '#1e293b', marginBottom: 16 },
  label: { fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 6 },
  input: { width: '100%', padding: '10px 14px', borderRadius: 10, border: '1px solid #e2e8f0', fontSize: 13, color: '#1e293b', outline: 'none', fontFamily: 'inherit', background: '#f8fafc' },
}

const RARITY_ORDER = ['SSR', 'SAR', 'BWR', 'CHR', 'UR', 'SR', 'AR', 'HR', 'MUR', 'MA', 'RR']
const SOURCE_LABELS = {
  SCRYDEX_EN:   { label: 'scrydex EN', color: '#15803d', bg: '#f0fdf4', border: '#bbf7d0' },
  SCRYDEX_JP:   { label: 'scrydex JP', color: '#1d4ed8', bg: '#eff6ff', border: '#bfdbfe' },
  KO_ESTIMATED: { label: 'KO 예상가',  color: '#7c3aed', bg: '#fdf4ff', border: '#e9d5ff' },
  NAVER_CAFE:   { label: '네이버 카페', color: '#d97706', bg: '#fffbeb', border: '#fde68a' },
  BUNJANG:      { label: '번개장터',   color: '#dc2626', bg: '#fef2f2', border: '#fecaca' },
}

function InfoTile({ label, value, sub, color = '#6366f1' }) {
  return (
    <div style={{ background: '#f8fafc', borderRadius: 12, padding: '16px', border: '1px solid #f1f5f9', flex: 1 }}>
      <div style={S.label}>{label}</div>
      <div style={{ fontSize: 22, fontWeight: 800, color: '#1e293b', letterSpacing: -0.5 }}>{value ?? '—'}</div>
      {sub && <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 4 }}>{sub}</div>}
    </div>
  )
}

function SourceBadge({ source }) {
  const s = SOURCE_LABELS[source] ?? { label: source, color: '#64748b', bg: '#f8fafc', border: '#e2e8f0' }
  return (
    <span style={{
      fontSize: 11, fontWeight: 700, padding: '3px 8px', borderRadius: 99,
      background: s.bg, color: s.color, border: `1px solid ${s.border}`,
    }}>{s.label}</span>
  )
}

export default function Price() {
  const [coeff, setCoeff]             = useState(null)
  const [coeffLoading, setCoeffLoading] = useState(true)
  const [rarityCoefs, setRarityCoefs] = useState(RARITY_ORDER.map(rarity => ({ rarity, coefficient: null })))
  const [history, setHistory]         = useState([])
  const [lookup, setLookup]           = useState({ cardId: '', result: null, loading: false })
  const [fetching, setFetching]       = useState(false)
  const [syncResult, setSyncResult]   = useState(null)
  const [snapshotStats, setSnapshotStats] = useState(null)
  const [adjustment, setAdjustment]   = useState(null)   // 현재 보정 계수
  const [adjInput, setAdjInput]       = useState('')      // 입력값
  const [adjSaving, setAdjSaving]     = useState(false)
  const [adjResult, setAdjResult]     = useState(null)
  // RAW/PSA10 환산 비율 (PR-RATIO). PSA10만 있는 카드의 추정 RAW 계산용.
  const [ratios, setRatios]           = useState([])
  const [ratiosLoading, setRatiosLoading] = useState(false)
  const [ratiosRecomputing, setRatiosRecomputing] = useState(false)

  function parseRarityCoefficient(payload) {
    const data = payload?.data ?? payload
    if (typeof data === 'number') return data
    if (typeof data?.coefficient === 'number') return data.coefficient
    if (typeof data?.price === 'number') return data.price / 10000
    return null
  }

  function loadCoefficient() {
    setCoeffLoading(true)
    Promise.all([
      api.get('/prices/coefficient'),
      api.get('/prices/coefficient/history', { params: { days: 30 } }),
      Promise.all(RARITY_ORDER.map(rarity =>
        api.get(`/prices/coefficient/rarity/${rarity}`)
          .then(res => ({ rarity, coefficient: parseRarityCoefficient(res.data) }))
          .catch(() => ({ rarity, coefficient: null }))
      )),
      api.get('/admin/stats/snapshots').catch(() => null),
      api.get('/prices/admin/market-adjustment').catch(() => null),
    ]).then(([coeffRes, histRes, rarityResults, snapRes, adjRes]) => {
      setCoeff(coeffRes.data?.data ?? null)
      setHistory(histRes.data?.data ?? [])
      setRarityCoefs(rarityResults)
      setSnapshotStats(snapRes?.data?.data ?? null)
      const f = adjRes?.data?.data?.factor ?? 1.0
      setAdjustment(f)
      setAdjInput(f.toFixed(2))
    }).catch(() => {})
     .finally(() => setCoeffLoading(false))
  }

  useEffect(() => { loadCoefficient() }, [])

  function loadRatios() {
    setRatiosLoading(true)
    api.get('/admin/raw-psa10-ratios')
      .then(res => setRatios(res.data?.data?.ratios ?? []))
      .catch(() => setRatios([]))
      .finally(() => setRatiosLoading(false))
  }
  function recomputeRatios() {
    setRatiosRecomputing(true)
    api.post('/admin/raw-psa10-ratios/recompute')
      .then(() => loadRatios())
      .finally(() => setRatiosRecomputing(false))
  }
  useEffect(() => { loadRatios() }, [])

  function fetchPrices() {
    if (!confirm('DB에 저장된 최신 scrydex 스냅샷 기반으로 KO 예상가를 재계산합니다.\n(scrydex 스크래퍼는 별도 Python 배치로 실행됩니다)')) return
    setFetching(true)
    setSyncResult(null)
    api.post('/prices/admin/refresh-ko-estimates')
      .then(r => {
        const d = r.data?.data
        setSyncResult({ ok: true, ...d })
        loadCoefficient()
      })
      .catch(() => setSyncResult({ ok: false }))
      .finally(() => setFetching(false))
  }

  function lookupPrice() {
    const id = lookup.cardId.trim()
    if (!id) return
    setLookup(l => ({ ...l, loading: true, result: null }))
    Promise.all([
      api.get(`/cards/${id}`),
      api.get(`/prices/cards/${id}/ko-price`).catch(() => null),
    ]).then(([cardRes, priceRes]) => {
      const card  = cardRes.data?.data
      const price = priceRes?.data?.data
      setLookup(l => ({ ...l, loading: false, result: { card, price } }))
    }).catch(() => {
      setLookup(l => ({ ...l, loading: false, result: 'error' }))
    })
  }

  function saveAdjustment() {
    const val = parseFloat(adjInput)
    if (isNaN(val) || val <= 0 || val > 5) { alert('0 초과 5 이하의 값을 입력하세요.'); return }
    const change = ((val - adjustment) * 100).toFixed(1)
    const sign = val > adjustment ? '+' : ''
    if (!confirm(
      `⚠️ 시장 보정 계수를 변경합니다.\n\n` +
      `현재: ${adjustment?.toFixed(2)}  →  변경: ${val.toFixed(2)}  (${sign}${change}%)\n\n` +
      `전체 ${3800 .toLocaleString()}장 이상의 KO 예상가가 즉시 재계산됩니다.\n` +
      `완료까지 수 초 소요되며, 앱 시세에 즉시 반영됩니다.\n\n` +
      `계속하시겠습니까?`
    )) return
    setAdjSaving(true)
    setAdjResult(null)
    api.post('/prices/admin/market-adjustment', null, { params: { factor: val } })
      .then(r => {
        const d = r.data?.data
        setAdjustment(val)
        setAdjResult({ ok: true, savedCount: d?.savedCount, ratio: d?.ratio })
        loadCoefficient()
      })
      .catch(() => setAdjResult({ ok: false }))
      .finally(() => setAdjSaving(false))
  }

  const calcAt = coeff?.calculatedAt ? coeff.calculatedAt.slice(0, 16).replace('T', ' ') : null

  return (
    <div style={S.page}>
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 6 }}>
        <div>
          <div style={{ fontSize: 22, fontWeight: 700, color: '#1e293b', letterSpacing: -0.5 }}>시세 관리</div>
          <div style={{ fontSize: 13, color: '#94a3b8', marginTop: 3 }}>scrydex 기반 한국 시장 계수 및 카드 시세</div>
        </div>
        <button onClick={fetchPrices} disabled={fetching} style={{
          display: 'flex', alignItems: 'center', gap: 6,
          padding: '9px 16px', borderRadius: 10, border: 'none', cursor: fetching ? 'not-allowed' : 'pointer',
          background: fetching ? '#cbd5e1' : 'linear-gradient(135deg, #6366f1, #4f46e5)',
          color: '#fff', fontSize: 13, fontWeight: 600, fontFamily: 'inherit',
        }}>
          <Zap size={13} />
          {fetching ? 'KO 예상가 재계산 중...' : 'KO 예상가 재계산'}
        </button>
      </div>

      <div style={{ fontSize: 11, color: calcAt ? '#10b981' : '#94a3b8', marginBottom: syncResult ? 12 : 24, fontWeight: 500 }}>
        {calcAt ? `마지막 계산: ${calcAt}` : '아직 계산된 데이터 없음'}
      </div>

      {/* 동기화 결과 */}
      {syncResult && (
        <div style={{
          marginBottom: 16, padding: '14px 18px', borderRadius: 12,
          background: syncResult.ok ? '#f0fdf4' : '#fef2f2',
          border: `1px solid ${syncResult.ok ? '#bbf7d0' : '#fecaca'}`,
          display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap',
        }}>
          {syncResult.ok
            ? <CheckCircle size={16} color="#16a34a" />
            : <XCircle size={16} color="#dc2626" />}
          <span style={{ fontSize: 13, fontWeight: 700, color: syncResult.ok ? '#15803d' : '#dc2626' }}>
            {syncResult.ok ? 'KO 예상가 재계산 완료' : '재계산 실패'}
          </span>
          {syncResult.ok && (
            <>
              <span style={{ fontSize: 12, color: '#374151' }}>
                저장 <b>{(syncResult.savedCount ?? 0).toLocaleString()}</b>장
              </span>
              <span style={{ fontSize: 12, color: '#6b7280' }}>·</span>
              <span style={{ fontSize: 12, color: '#374151' }}>
                EN 소스 <b>{(syncResult.enSource ?? 0).toLocaleString()}</b>장
              </span>
              <span style={{ fontSize: 12, color: '#6b7280' }}>·</span>
              <span style={{ fontSize: 12, color: '#374151' }}>
                JP 소스 <b>{(syncResult.jpSource ?? 0).toLocaleString()}</b>장
              </span>
              <span style={{ fontSize: 12, color: '#6b7280' }}>·</span>
              <span style={{ fontSize: 12, color: '#374151' }}>
                계수 <b>{syncResult.coefficient?.toFixed(3)}</b>
              </span>
            </>
          )}
        </div>
      )}

      {/* 시장 지표 카드 */}
      <div style={{ ...S.card, padding: '22px 24px', marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16 }}>
          <TrendingUp size={15} color="#6366f1" />
          <div style={S.h2}>현재 시장 지표</div>
          <button onClick={loadCoefficient} style={{ marginLeft: 'auto', background: 'none', border: 'none', cursor: 'pointer', color: '#94a3b8' }}>
            <RefreshCw size={13} style={{ animation: coeffLoading ? 'spin 1s linear infinite' : 'none' }} />
          </button>
        </div>

        {coeffLoading ? (
          <div style={{ textAlign: 'center', padding: '24px', color: '#94a3b8', fontSize: 13 }}>불러오는 중...</div>
        ) : coeff ? (
          <>
            <div style={{ display: 'flex', gap: 12, marginBottom: 16 }}>
              <InfoTile label="기준 계수 (글로벌)" value={coeff.coefficient?.toFixed(3)} sub="KO 가격 / 해외 환산가 비율 (SSR/SAR 제외)" />
              <InfoTile label="USD/KRW 환율" value={`${Math.round(coeff.exchangeRate).toLocaleString()}원`} sub="계산 시 사용한 환율" />
              <InfoTile label="샘플 카드 수" value={`${coeff.sampleSize?.toLocaleString()}장`} sub="계수 계산에 사용된 고레어 카드" />
            </div>
            <div style={{ padding: '14px 16px', borderRadius: 12, background: '#f0fdf4', border: '1px solid #bbf7d0' }}>
              <div style={{ fontSize: 12, color: '#15803d', fontWeight: 700, marginBottom: 6 }}>계산식 (레어도별 계수 적용)</div>
              <div style={{ fontSize: 13, color: '#166534', lineHeight: 1.8 }}>
                <b>일반 카드:</b> KO 예상가 = scrydex JP (JPY) × JPY/KRW × <i>jp_레어도계수</i><br />
                <span style={{ paddingLeft: 16, display: 'block' }}>또는 scrydex EN (USD) × USD/KRW × <i>en_레어도계수</i> (JP 없을 때)</span>
                <b>프로모 전용:</b> JP RAW 직접 사용 → JP PSA10 fallback → EN RAW<br />
                <span style={{ fontSize: 11, color: '#94a3b8' }}>
                  예시 (UR, JP RAW ¥10,000): {Math.round(10000 * 9.5).toLocaleString()}원 × {
                    rarityCoefs.find(r => r.rarity === 'UR')?.coefficient?.toFixed(3) ?? coeff.coefficient?.toFixed(3)
                  } ≈ {Math.round(10000 * 9.5 * (rarityCoefs.find(r => r.rarity === 'UR')?.coefficient ?? coeff.coefficient)).toLocaleString()}원
                </span>
              </div>
            </div>
          </>
        ) : (
          <div style={{ textAlign: 'center', padding: '24px', color: '#94a3b8', fontSize: 13 }}>
            데이터를 불러올 수 없습니다. 백엔드 서버를 확인하세요.
          </div>
        )}
      </div>

      {/* 오늘 수집 현황 */}
      <div style={{ ...S.card, padding: '22px 24px', marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16 }}>
          <Database size={15} color="#6366f1" />
          <div style={S.h2}>스냅샷 수집 현황</div>
          <span style={{ marginLeft: 'auto', fontSize: 11, color: '#94a3b8' }}>
            {snapshotStats?.date ?? '—'}
          </span>
        </div>
        {snapshotStats ? (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 10 }}>
            {['SCRYDEX_EN', 'SCRYDEX_JP', 'KO_ESTIMATED', 'NAVER_CAFE', 'BUNJANG'].map(src => {
              const todayN = snapshotStats.today?.[src] ?? 0
              const yesterN = snapshotStats.yesterday?.[src] ?? 0
              const delta = todayN - yesterN
              // 2026-05-29 P0 #5: 톤다운 — today=0 이면 "어제 대비 -N 빨강" 표시 안 함.
              //   대신 회색 "오늘 batch 대기중". 11AM 시점에 정상 batch 시간 전이라도 장애처럼 안 보이게.
              //   actual 장애 판단은 별도 TF (project_prod_cron_architecture 참조).
              const noToday = todayN === 0
              return (
                <div key={src} style={{ background: '#f8fafc', borderRadius: 12, padding: '14px 16px', border: '1px solid #f1f5f9' }}>
                  <div style={{ marginBottom: 8 }}><SourceBadge source={src} /></div>
                  <div style={{ fontSize: 22, fontWeight: 800, color: noToday ? '#94a3b8' : '#1e293b' }}>
                    {todayN.toLocaleString()}
                  </div>
                  <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 4 }}>
                    {noToday ? (
                      <span style={{ color: '#94a3b8' }}>
                        오늘 batch 대기중 · 어제 {yesterN.toLocaleString()}
                      </span>
                    ) : (
                      <>
                        오늘 수집
                        {yesterN > 0 && (
                          <span style={{ marginLeft: 6, color: delta > 0 ? '#16a34a' : delta < 0 ? '#dc2626' : '#94a3b8', fontWeight: 600 }}>
                            ({delta >= 0 ? '+' : ''}{delta} vs 어제)
                          </span>
                        )}
                      </>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        ) : (
          <div style={{ textAlign: 'center', padding: '24px', color: '#94a3b8', fontSize: 13 }}>
            수집 데이터 없음
          </div>
        )}
      </div>

      {/* 시장 보정 계수 */}
      <div style={{ ...S.card, padding: '22px 24px', marginBottom: 16, border: '1px solid #fde68a', background: '#fffbeb' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
          <span style={{ fontSize: 16 }}>⚠️</span>
          <div style={{ fontSize: 15, fontWeight: 700, color: '#92400e' }}>시장 보정 계수</div>
        </div>
        <div style={{ fontSize: 12, color: '#b45309', marginBottom: 16, lineHeight: 1.6 }}>
          전체 레어도 계수에 곱해지는 전역 배율입니다. 변경 시 <b>3,800장 이상의 KO 예상가가 즉시 재계산</b>되며 앱 시세에 바로 반영됩니다.<br />
          시장 과열·침체 등 일시적 시장 변동을 반영할 때만 조정하세요.
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div>
            <div style={{ fontSize: 11, color: '#92400e', fontWeight: 700, marginBottom: 4 }}>현재 보정 계수</div>
            <div style={{ fontSize: 28, fontWeight: 800, color: '#92400e', letterSpacing: -1 }}>
              {adjustment != null ? `×${adjustment.toFixed(2)}` : '—'}
            </div>
          </div>
          <div style={{ width: 1, height: 48, background: '#fde68a', margin: '0 8px' }} />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 11, color: '#92400e', fontWeight: 700, marginBottom: 4 }}>새 보정 계수</div>
            <div style={{ display: 'flex', gap: 8 }}>
              <input
                type="number" step="0.01" min="0.5" max="3"
                value={adjInput}
                onChange={e => setAdjInput(e.target.value)}
                style={{ width: 100, padding: '8px 12px', borderRadius: 8, border: '1px solid #fcd34d', fontSize: 14, fontWeight: 700, color: '#92400e', background: '#fff', outline: 'none' }}
              />
              <button
                onClick={saveAdjustment}
                disabled={adjSaving}
                style={{
                  padding: '8px 18px', borderRadius: 8, border: 'none', cursor: adjSaving ? 'not-allowed' : 'pointer',
                  background: adjSaving ? '#d1d5db' : '#d97706', color: '#fff', fontSize: 13, fontWeight: 700, fontFamily: 'inherit',
                }}>
                {adjSaving ? '재계산 중...' : '적용 및 재계산'}
              </button>
            </div>
          </div>
          {adjResult && (
            <div style={{ fontSize: 12, color: adjResult.ok ? '#15803d' : '#dc2626', fontWeight: 600 }}>
              {adjResult.ok
                ? `✓ 완료 — ${adjResult.savedCount?.toLocaleString()}장 재계산 (비율 ×${adjResult.ratio})`
                : '✗ 오류 발생'}
            </div>
          )}
        </div>
      </div>

      {/* 레어도별 계수 현황 */}
      <div style={{ ...S.card, padding: '22px 24px', marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16 }}>
          <Activity size={15} color="#6366f1" />
          <div style={S.h2}>레어도별 계수 현황</div>
        </div>

        <div style={{ border: '1px solid #f1f5f9', borderRadius: 12, overflow: 'hidden' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '90px 110px 190px 1fr', gap: 12, padding: '11px 14px', background: '#f8fafc', borderBottom: '1px solid #f1f5f9' }}>
            {['레어도', '계수', 'JP 10만엔 기준 KO 예상가', '바 차트'].map(label => (
              <div key={label} style={{ fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.5 }}>{label}</div>
            ))}
          </div>
          {(() => {
            const maxCoef = Math.max(...rarityCoefs.map(r => r.coefficient ?? 0), 1)
            return rarityCoefs.map(({ rarity, coefficient }) => {
            const hasValue = typeof coefficient === 'number' && Number.isFinite(coefficient)
            const width = hasValue ? `${Math.min((coefficient / maxCoef) * 100, 100)}%` : '0%'
            return (
              <div key={rarity} style={{ display: 'grid', gridTemplateColumns: '90px 110px 190px 1fr', gap: 12, alignItems: 'center', padding: '12px 14px', borderBottom: '1px solid #f8fafc' }}>
                <div style={{ fontSize: 13, fontWeight: 800, color: '#1e293b' }}>{rarity}</div>
                <div style={{ fontSize: 13, fontWeight: 700, color: hasValue ? '#4f46e5' : '#94a3b8' }}>{hasValue ? coefficient.toFixed(3) : '-'}</div>
                <div style={{ fontSize: 13, color: '#334155', fontWeight: 600 }}>
                  {hasValue ? `${Math.round(coefficient * 100000 * 9.5).toLocaleString()}원` : '-'}
                </div>
                <div style={{ width: '100%', height: 8, borderRadius: 999, background: '#eef2ff', overflow: 'hidden' }}>
                  <div style={{ width, height: 8, borderRadius: 999, background: hasValue ? 'linear-gradient(90deg, #6366f1, #22c55e)' : 'transparent' }} />
                </div>
              </div>
            )
            })
          })()}
        </div>
        <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 10 }}>
          * JP 10만엔 기준 예상가 = ¥100,000 × 9.5 (KRW/JPY) × 계수 (환율 9.5 가정)
        </div>
      </div>

      {/* RAW / PSA10 환산 비율 (PR-RATIO) */}
      <div style={{ ...S.card, padding: '22px 24px', marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16 }}>
          <Database size={15} color="#6366f1" />
          <div style={S.h2}>RAW / PSA10 환산 비율</div>
          <span style={{ fontSize: 11, color: '#94a3b8', marginLeft: 'auto' }}>
            PSA10 가격 × ratio_median = 추정 RAW. 매일 23:55 자동 갱신.
          </span>
          <button onClick={recomputeRatios} disabled={ratiosRecomputing}
            style={{ padding: '7px 14px', borderRadius: 8, border: '1px solid #6366f1',
              background: ratiosRecomputing ? '#f1f5f9' : '#fff', color: '#6366f1',
              fontSize: 12, fontWeight: 700, cursor: ratiosRecomputing ? 'not-allowed' : 'pointer' }}>
            {ratiosRecomputing ? '계산 중...' : '지금 재계산'}
          </button>
        </div>

        {ratiosLoading ? (
          <div style={{ textAlign: 'center', padding: '32px', color: '#94a3b8', fontSize: 13 }}>
            로딩 중...
          </div>
        ) : ratios.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '32px', color: '#94a3b8', fontSize: 13 }}>
            비율 데이터 없음. 우상단 "지금 재계산" 버튼을 누르세요.
          </div>
        ) : (
          <div style={{ border: '1px solid #f1f5f9', borderRadius: 12, overflow: 'hidden' }}>
            <div style={{
              display: 'grid',
              gridTemplateColumns: '120px 80px 80px 90px 100px 140px 1fr',
              gap: 12, padding: '11px 14px', background: '#f8fafc',
              borderBottom: '1px solid #f1f5f9',
            }}>
              {['source', 'rarity', 'window', 'samples', 'median', 'p25 ~ p75', 'computed'].map(label => (
                <div key={label} style={{ fontSize: 11, fontWeight: 700, color: '#94a3b8',
                  textTransform: 'uppercase', letterSpacing: 0.5 }}>{label}</div>
              ))}
            </div>
            {ratios.map((r, i) => {
              const isJp = r.source === 'SCRYDEX_JP'
              const lowSample = r.sampleCount < 30
              return (
                <div key={`${r.source}-${r.rarityCode}-${i}`} style={{
                  display: 'grid',
                  gridTemplateColumns: '120px 80px 80px 90px 100px 140px 1fr',
                  gap: 12, alignItems: 'center', padding: '12px 14px',
                  borderBottom: '1px solid #f8fafc',
                }}>
                  <SourceBadge source={r.source} />
                  <div style={{ fontSize: 13, fontWeight: 800, color: '#1e293b' }}>{r.rarityCode}</div>
                  <div style={{ fontSize: 12, color: '#64748b' }}>{r.windowDays}d</div>
                  <div style={{ fontSize: 13, fontWeight: 700, color: lowSample ? '#f59e0b' : '#334155' }}>
                    {r.sampleCount}
                  </div>
                  <div style={{ fontSize: 14, fontWeight: 800, color: '#15803d' }}>
                    {(Number(r.ratioMedian) * 100).toFixed(2)}%
                  </div>
                  <div style={{ fontSize: 12, color: '#64748b', fontFamily: 'monospace' }}>
                    {r.ratioP25 != null ? (Number(r.ratioP25) * 100).toFixed(2) : '-'}% ~
                    {r.ratioP75 != null ? (Number(r.ratioP75) * 100).toFixed(2) : '-'}%
                  </div>
                  <div style={{ fontSize: 11, color: '#94a3b8' }}>
                    {String(r.computedAt).replace('T', ' ').slice(0, 16)}
                  </div>
                </div>
              )
            })}
          </div>
        )}
        <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 10 }}>
          * 14일 윈도우 우선, 샘플 부족 시 30일 확장. IQR trim 후 median/p25/p75. samples &lt; 30은 주의(노란).
        </div>
      </div>

      {/* 계수 추세 그래프 */}
      <div style={{ ...S.card, padding: '22px 24px', marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <TrendingUp size={15} color="#6366f1" />
            <div style={S.h2}>계수 추세 · 최근 30일</div>
          </div>
          <span style={{ fontSize: 11, color: '#94a3b8' }}>매일 새벽 4시 30분 자동 갱신</span>
        </div>

        {history.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '32px', color: '#94a3b8', fontSize: 13 }}>
            아직 히스토리 데이터가 없습니다. 스케줄러가 매일 새벽에 자동으로 적재합니다.
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={200}>
            <LineChart data={history} margin={{ top: 4, right: 16, left: -10, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" vertical={false} />
              <XAxis dataKey="date" tick={{ fontSize: 11, fill: '#94a3b8' }} axisLine={false} tickLine={false}
                tickFormatter={d => d.slice(5)} />
              <YAxis tick={{ fontSize: 11, fill: '#94a3b8' }} axisLine={false} tickLine={false}
                domain={['auto', 'auto']} tickFormatter={v => v.toFixed(2)} />
              <Tooltip
                formatter={(v) => [v.toFixed(3), '계수']}
                labelFormatter={l => l}
                contentStyle={{ borderRadius: 10, border: '1px solid #e2e8f0', fontSize: 12 }}
              />
              <ReferenceLine y={1.0} stroke="#e2e8f0" strokeDasharray="4 4" label={{ value: '1.0', fontSize: 10, fill: '#cbd5e1' }} />
              <Line type="monotone" dataKey="coefficient" stroke="#6366f1" strokeWidth={2.5}
                dot={{ r: 4, fill: '#6366f1', strokeWidth: 0 }} activeDot={{ r: 6 }} />
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* 카드 시세 조회 */}
      <div style={{ ...S.card, padding: '22px 24px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16 }}>
          <Search size={15} color="#6366f1" />
          <div style={S.h2}>카드 시세 조회</div>
        </div>

        <div style={{ display: 'flex', gap: 8, marginBottom: lookup.result ? 16 : 0 }}>
          <input
            value={lookup.cardId}
            onChange={e => setLookup(l => ({ ...l, cardId: e.target.value, result: null }))}
            onKeyDown={e => e.key === 'Enter' && lookupPrice()}
            placeholder="카드 ID 입력 (예: sv6-001)"
            style={{ ...S.input, flex: 1 }}
          />
          <button onClick={lookupPrice} disabled={lookup.loading} style={{
            padding: '10px 20px', borderRadius: 10, border: 'none', cursor: lookup.loading ? 'not-allowed' : 'pointer',
            background: 'linear-gradient(135deg, #6366f1, #4f46e5)',
            color: '#fff', fontSize: 13, fontWeight: 600, fontFamily: 'inherit', flexShrink: 0,
          }}>
            {lookup.loading ? <RefreshCw size={13} style={{ animation: 'spin 1s linear infinite' }} /> : '조회'}
          </button>
        </div>

        {lookup.result === 'error' && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '12px 14px', borderRadius: 10, background: '#fef2f2', border: '1px solid #fecaca', color: '#dc2626', fontSize: 13 }}>
            <XCircle size={14} /> 카드를 찾을 수 없습니다
          </div>
        )}

        {lookup.result && lookup.result !== 'error' && lookup.result.card && (
          <div style={{ background: '#f8fafc', borderRadius: 12, padding: '18px', border: '1px solid #f1f5f9' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 14 }}>
              <CheckCircle size={14} color="#16a34a" />
              <span style={{ fontSize: 14, fontWeight: 700, color: '#1e293b' }}>
                {lookup.result.card.name}
              </span>
              <span style={{ fontSize: 11, color: '#94a3b8', marginLeft: 4 }}>
                {lookup.result.card.rarityCode} · {lookup.result.card.language}
              </span>
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 10 }}>
              {[
                { label: 'KO 예상가', value: lookup.result.price?.koEstimatedPrice ? `${lookup.result.price.koEstimatedPrice.toLocaleString()}원` : '-', highlight: true },
                { label: 'EN RAW (scrydex)', value: lookup.result.price?.enRawPrice ? `$${lookup.result.price.enRawPrice}` : '-' },
                { label: '세트', value: lookup.result.card.productId ?? '-' },
              ].map(({ label, value, highlight }) => (
                <div key={label} style={{ background: '#fff', borderRadius: 10, padding: '12px 14px', border: `1px solid ${highlight ? '#c7d2fe' : '#f1f5f9'}` }}>
                  <div style={{ fontSize: 10, color: '#94a3b8', fontWeight: 700, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 5 }}>{label}</div>
                  <div style={{ fontSize: 16, fontWeight: 800, color: highlight ? '#4f46e5' : '#1e293b' }}>{value}</div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
