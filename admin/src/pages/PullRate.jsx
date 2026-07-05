import { useEffect, useMemo, useRef, useState } from 'react'
import { Search, X, Calculator, Copy, Check } from 'lucide-react'
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts'
import api from '../api'
import { atLeastOne, unionIndependent, trialsToReach } from '../lib/pullMath'

const S = {
  page:   { padding: '32px 36px', minHeight: '100%', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' },
  h1:     { fontSize: 22, fontWeight: 700, color: '#1e293b', letterSpacing: -0.5 },
  sub:    { fontSize: 13, color: '#94a3b8', marginTop: 3 },
  card:   { background: '#fff', borderRadius: 16, border: '1px solid #e8edf4', boxShadow: '0 1px 3px rgba(0,0,0,0.04)', padding: 20 },
  lbl:    { fontSize: 11, fontWeight: 600, color: '#64748b', marginBottom: 4, display: 'block' },
  inp:    { width: '100%', boxSizing: 'border-box', padding: '9px 12px', borderRadius: 8, border: '1px solid #e2e8f0', fontSize: 13, color: '#1e293b', outline: 'none', fontFamily: 'inherit' },
  section:{ fontSize: 13, fontWeight: 700, color: '#1e293b', marginBottom: 12 },
  fieldset:{ border: '1px solid #eef2f7', borderRadius: 12, padding: 14, background: '#fafbff', marginBottom: 14 },
  fsTitle:{ fontSize: 12, fontWeight: 700, color: '#4f46e5', marginBottom: 10 },
}

// 확률 표시 — 크기에 따라 유효자릿수 조절 (0.0001% 급도 읽히게)
const fmtPct = (p) => {
  if (p == null || !isFinite(p)) return '—'
  const v = p * 100
  if (v >= 100) return '100%'
  if (v >= 10)  return v.toFixed(1) + '%'
  if (v >= 1)   return v.toFixed(2) + '%'
  if (v >= 0.01) return v.toFixed(3) + '%'
  return v.toPrecision(2) + '%'
}
const fmtWon = (n) => (n == null || !isFinite(n) ? '—' : Math.round(n).toLocaleString('ko-KR') + '원')
const fmtNum = (n) => (n == null || !isFinite(n) ? '—' : Math.round(n).toLocaleString('ko-KR'))
const fmtBoxes = (n) => (n == null || !isFinite(n) ? '—' : n.toLocaleString('ko-KR', { maximumFractionDigits: 1 }))

function RarityBadge({ rarity }) {
  const colors = {
    UR:  { bg: '#fefce8', color: '#ca8a04', border: '#fef08a' },
    SAR: { bg: '#fdf4ff', color: '#a21caf', border: '#f0abfc' },
    SR:  { bg: '#eff6ff', color: '#1d4ed8', border: '#bfdbfe' },
    AR:  { bg: '#f0fdf4', color: '#15803d', border: '#bbf7d0' },
    RR:  { bg: '#fff7ed', color: '#c2410c', border: '#fed7aa' },
    HR:  { bg: '#fff1f2', color: '#be123c', border: '#fecdd3' },
    MUR: { bg: '#fffbeb', color: '#b45309', border: '#fde68a' },
  }
  const s = colors[rarity] ?? { bg: '#f8fafc', color: '#94a3b8', border: '#e2e8f0' }
  return (
    <span style={{ fontSize: 11, fontWeight: 700, padding: '3px 8px', borderRadius: 99, background: s.bg, color: s.color, border: `1px solid ${s.border}` }}>
      {rarity}
    </span>
  )
}

// 카드 검색 → 선택. 선택 시 시세를 카드값 기본값으로 넘김(onSelect 콜백에서 처리)
function CardPicker({ selected, onSelect }) {
  const [query, setQuery] = useState('')
  const [results, setResults] = useState([])
  const [open, setOpen] = useState(false)
  const boxRef = useRef(null)

  useEffect(() => {
    if (!query.trim()) return
    const t = setTimeout(() => {
      api.get('/admin/cards', { params: { page: 0, size: 8, search: query.trim() } })
        .then(r => { setResults(r.data?.data?.content ?? []); setOpen(true) })
        .catch(() => setResults([]))
    }, 300)
    return () => clearTimeout(t)
  }, [query])

  const handleQueryChange = (v) => {
    setQuery(v)
    if (!v.trim()) { setResults([]); setOpen(false) }
  }

  useEffect(() => {
    const h = (e) => { if (boxRef.current && !boxRef.current.contains(e.target)) setOpen(false) }
    document.addEventListener('mousedown', h)
    return () => document.removeEventListener('mousedown', h)
  }, [])

  if (selected) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 12px', borderRadius: 10, border: '1px solid #c7d2fe', background: '#eef2ff' }}>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ fontSize: 13, fontWeight: 700, color: '#1e293b', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{selected.nameKo ?? selected.nameEn ?? '-'}</div>
          <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{selected.setName ?? '-'}</div>
        </div>
        <RarityBadge rarity={selected.rarity} />
        <button onClick={() => onSelect(null)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#94a3b8', padding: 2, display: 'flex' }}><X size={15} /></button>
      </div>
    )
  }

  return (
    <div ref={boxRef} style={{ position: 'relative' }}>
      <Search size={14} style={{ position: 'absolute', left: 12, top: 12, color: '#94a3b8' }} />
      <input
        style={{ ...S.inp, paddingLeft: 34 }}
        placeholder="카드 검색 (선택사항 — 라벨·시세 자동)"
        value={query}
        onChange={e => handleQueryChange(e.target.value)}
        onFocus={() => results.length > 0 && setOpen(true)}
      />
      {open && results.length > 0 && (
        <div style={{ position: 'absolute', top: '100%', left: 0, right: 0, marginTop: 4, background: '#fff', borderRadius: 10, border: '1px solid #e2e8f0', boxShadow: '0 8px 24px rgba(0,0,0,0.1)', zIndex: 20, maxHeight: 280, overflow: 'auto' }}>
          {results.map(c => (
            <div key={c.id}
              onClick={() => { onSelect(c); setQuery(''); setOpen(false) }}
              onMouseEnter={e => e.currentTarget.style.background = '#f8fafc'}
              onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
              style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '9px 12px', cursor: 'pointer', borderBottom: '1px solid #f8fafc' }}>
              <div style={{ minWidth: 0, flex: 1 }}>
                <div style={{ fontSize: 12, fontWeight: 600, color: '#1e293b', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{c.nameKo ?? c.nameEn ?? '-'}</div>
                <div style={{ fontSize: 10, color: '#94a3b8', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{c.setName ?? '-'}{c.koEstimatedPrice ? ` · ${fmtWon(c.koEstimatedPrice)}` : ''}</div>
              </div>
              <RarityBadge rarity={c.rarity} />
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function NumField({ label, value, onChange, hint, min = 0, step = 'any', suffix, disabled }) {
  return (
    <div>
      {label && <label style={S.lbl}>{label}{hint && <span style={{ color: '#94a3b8', fontWeight: 500 }}> · {hint}</span>}</label>}
      <div style={{ position: 'relative' }}>
        <input type="number" min={min} step={step} disabled={disabled}
          style={{ ...S.inp, paddingRight: suffix ? 42 : 12, background: disabled ? '#f1f5f9' : '#fff', color: disabled ? '#94a3b8' : '#1e293b' }}
          value={value} onChange={e => onChange(e.target.value)} />
        {suffix && <span style={{ position: 'absolute', right: 12, top: '50%', transform: 'translateY(-50%)', fontSize: 12, color: '#94a3b8' }}>{suffix}</span>}
      </div>
    </div>
  )
}

function StatBox({ label, value, sub, accent }) {
  return (
    <div style={{ padding: '14px 16px', borderRadius: 12, background: accent ? 'linear-gradient(135deg, #eef2ff, #f5f3ff)' : '#f8fafc', border: `1px solid ${accent ? '#c7d2fe' : '#f1f5f9'}` }}>
      <div style={{ fontSize: 11, fontWeight: 600, color: '#64748b' }}>{label}</div>
      <div style={{ fontSize: accent ? 24 : 18, fontWeight: 800, color: accent ? '#4f46e5' : '#1e293b', marginTop: 4, fontVariantNumeric: 'tabular-nums' }}>{value}</div>
      {sub && <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 3 }}>{sub}</div>}
    </div>
  )
}

export default function PullRate() {
  const [card, setCard] = useState(null)

  // 제품 구조
  const [packsPerBox, setPacksPerBox] = useState('30')
  const [boxesPerCarton, setBoxesPerCarton] = useState('30')

  // 대상 카드 풀 (출현율과 풀을 한 묶음으로 — 17종 함정 방지)
  const [poolName, setPoolName] = useState('')
  const [freqBoxes, setFreqBoxes] = useState('')   // N박스당
  const [freqCopies, setFreqCopies] = useState('1')// M장
  const [poolSize, setPoolSize] = useState('')     // 풀 내 카드 수
  const [weightMode, setWeightMode] = useState('equal')  // equal | manual
  const [manualWeight, setManualWeight] = useState('')   // %

  // 팩 위치 균등 가정 (1팩 환산 조건)
  const [packUniform, setPackUniform] = useState(true)

  // 갓팩 (선택 경로)
  const [godEnabled, setGodEnabled] = useState(false)
  const [godRateBoxes, setGodRateBoxes] = useState('')   // N박스당 1갓팩
  const [godTargetProb, setGodTargetProb] = useState('') // 갓팩 1개당 목표카드 %

  // 가격
  const [cardPrice, setCardPrice] = useState('')
  const [boxPrice, setBoxPrice] = useState('')
  const [packPrice, setPackPrice] = useState('')

  const [copied, setCopied] = useState(false)

  // 카드 선택 시 시세를 카드값 기본값으로 (effect 아님 — 핸들러에서 처리)
  const handleSelectCard = (c) => {
    setCard(c)
    if (c?.koEstimatedPrice && !cardPrice) setCardPrice(String(c.koEstimatedPrice))
  }

  const calc = useMemo(() => {
    const M = parseFloat(freqCopies), N = parseFloat(freqBoxes)
    if (!(M > 0) || !(N > 0)) return null
    const poolHitPerBox = M / N                       // 풀이 박스에 나올 확률
    let weight
    if (weightMode === 'equal') {
      const pool = parseFloat(poolSize)
      if (!(pool > 0)) return null
      weight = 1 / pool
    } else {
      const w = parseFloat(manualWeight)
      if (!(w > 0)) return null
      weight = w / 100
    }
    const pBoxNormal = Math.min(1, poolHitPerBox * weight)

    // 갓팩 경로 — 독립 가정으로 결합
    let pBoxGod = 0
    if (godEnabled) {
      const gr = parseFloat(godRateBoxes), gp = parseFloat(godTargetProb)
      if (gr > 0 && gp > 0) pBoxGod = Math.min(1, (1 / gr) * (gp / 100))
    }
    const pBox = unionIndependent(pBoxNormal, pBoxGod)
    if (!(pBox > 0)) return null

    const packs = parseFloat(packsPerBox)
    const pPack = (packUniform && packs > 0) ? pBox / packs : null   // 박스 내 1장·팩 위치 균등 가정에서만

    const cardW = parseFloat(cardPrice), boxW = parseFloat(boxPrice)
    const breakevenBoxes = (cardW > 0 && boxW > 0) ? Math.ceil(cardW / boxW) : null

    return {
      pBox, pPack, pBoxGod,
      packs: packs > 0 ? packs : null,
      carton: parseFloat(boxesPerCarton) > 0 ? parseFloat(boxesPerCarton) : null,
      avgBoxes: 1 / pBox,
      box50: trialsToReach(pBox, 0.5),
      box90: trialsToReach(pBox, 0.9),
      breakevenBoxes,
      pBreakeven: breakevenBoxes ? atLeastOne(pBox, breakevenBoxes) : null,
      boxPrice: boxW > 0 ? boxW : null,
      packPrice: parseFloat(packPrice) > 0 ? parseFloat(packPrice) : null,
      cardPrice: cardW > 0 ? cardW : null,
      expectedCost: boxW > 0 ? (1 / pBox) * boxW : null,
      isEqual: weightMode === 'equal',
    }
  }, [freqCopies, freqBoxes, weightMode, poolSize, manualWeight, godEnabled, godRateBoxes, godTargetProb, packsPerBox, boxesPerCarton, packUniform, cardPrice, boxPrice, packPrice])

  // 구매 단위별 확률 표
  const rows = useMemo(() => {
    if (!calc) return []
    const out = []
    if (calc.pPack != null) {
      out.push({ key: '1팩', n: 1, unit: 'pack', prob: atLeastOne(calc.pPack, 1), cost: calc.packPrice })
      out.push({ key: '5팩', n: 5, unit: 'pack', prob: atLeastOne(calc.pPack, 5), cost: calc.packPrice ? 5 * calc.packPrice : null })
    }
    const boxUnits = [
      { key: '1박스', n: 1 }, { key: '3박스', n: 3 }, { key: '5박스', n: 5 }, { key: '10박스', n: 10 },
    ]
    if (calc.carton) boxUnits.push({ key: `1카톤 (${fmtNum(calc.carton)}박스)`, n: calc.carton })
    for (const b of boxUnits) out.push({ key: b.key, n: b.n, unit: 'box', prob: atLeastOne(calc.pBox, b.n), cost: calc.boxPrice ? b.n * calc.boxPrice : null })
    return out
  }, [calc])

  // 누적 확률 곡선 (박스 단위, 90% 도달 또는 카톤까지)
  const chart = useMemo(() => {
    if (!calc) return []
    const maxN = Math.max(calc.carton || 0, isFinite(calc.box90) ? calc.box90 : 0, calc.breakevenBoxes || 0, 10)
    const cap = Math.min(maxN, 2000)
    const step = Math.max(1, Math.floor(cap / 60))
    const pts = []
    for (let n = 0; n <= cap; n += step) pts.push({ n, prob: +(atLeastOne(calc.pBox, n) * 100).toFixed(2) })
    if (pts.length === 0 || pts[pts.length - 1].n < cap) pts.push({ n: cap, prob: +(atLeastOne(calc.pBox, cap) * 100).toFixed(2) })
    return pts
  }, [calc])

  const cardName = card ? `${card.nameKo ?? card.nameEn}${card.rarity ? ` ${card.rarity}` : ''}` : '이 카드'

  // 인스타 콘텐츠용 복사 텍스트
  const contentText = useMemo(() => {
    if (!calc) return ''
    const L = []
    L.push(`🔥 ${cardName} — 몇 박스 안에 뽑아야 본전?`)
    L.push('')
    if (calc.cardPrice) L.push(`💰 카드 시세 ${fmtWon(calc.cardPrice)}${calc.boxPrice ? ` / 박스 ${fmtWon(calc.boxPrice)}` : ''}`)
    L.push(`🎴 1박스 확률 ${fmtPct(calc.pBox)}`)
    L.push(`📦 10박스 확률 ${fmtPct(atLeastOne(calc.pBox, 10))}`)
    if (calc.carton) L.push(`🏷️ 1카톤(${fmtNum(calc.carton)}박스) 확률 ${fmtPct(atLeastOne(calc.pBox, calc.carton))}`)
    L.push(`📊 평균 약 ${fmtBoxes(calc.avgBoxes)}박스당 1장`)
    if (calc.breakevenBoxes) L.push(`✅ 카드값 기준 본전 ${fmtNum(calc.breakevenBoxes)}박스 → 그 안에 뽑을 확률 ${fmtPct(calc.pBreakeven)}`)
    if (calc.isEqual) L.push('')
    if (calc.isEqual) L.push('※ 풀 내 균등 봉입 가정 추정치')
    L.push('')
    L.push('갖고 싶은 카드 확률이 궁금하면 댓글로 남겨주세요!')
    return L.join('\n')
  }, [calc, cardName])

  const doCopy = () => {
    if (!contentText) return
    navigator.clipboard?.writeText(contentText).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    }).catch(() => {})
  }

  const wBtn = (key, label) => (
    <button onClick={() => setWeightMode(key)} style={{
      flex: 1, padding: '7px 8px', borderRadius: 8, border: '1px solid', cursor: 'pointer',
      fontSize: 12, fontWeight: weightMode === key ? 700 : 500, fontFamily: 'inherit',
      background: weightMode === key ? '#6366f1' : '#fff', color: weightMode === key ? '#fff' : '#64748b',
      borderColor: weightMode === key ? '#6366f1' : '#e2e8f0',
    }}>{label}</button>
  )

  return (
    <div style={S.page}>
      <div style={{ marginBottom: 24 }}>
        <div style={S.h1}>확률 계산기</div>
        <div style={S.sub}>카드 뽑기 확률 + 본전 계산 · 콘텐츠 제작용 · 봉입률은 조사해서 입력</div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '380px 1fr', gap: 20, alignItems: 'start' }}>
        {/* ── 입력 ── */}
        <div style={S.card}>
          <div style={S.section}><Calculator size={14} style={{ verticalAlign: -2, marginRight: 6 }} />입력</div>

          <div style={{ marginBottom: 14 }}>
            <label style={S.lbl}>대상 카드</label>
            <CardPicker selected={card} onSelect={handleSelectCard} />
          </div>

          {/* 제품 구조 */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginBottom: 14 }}>
            <NumField label="팩 / 박스" value={packsPerBox} onChange={setPacksPerBox} step="1" suffix="팩" />
            <NumField label="박스 / 카톤" value={boxesPerCarton} onChange={setBoxesPerCarton} step="1" suffix="박스" />
          </div>

          {/* 대상 카드 풀 — 출현율과 풀을 한 묶음으로 */}
          <div style={S.fieldset}>
            <div style={S.fsTitle}>대상 카드 풀 <span style={{ color: '#94a3b8', fontWeight: 500 }}>· 출현율과 풀은 같은 묶음</span></div>
            <div style={{ marginBottom: 10 }}>
              <label style={S.lbl}>카드 풀 이름</label>
              <input style={S.inp} placeholder="예: 포켓몬 SAR" value={poolName} onChange={e => setPoolName(e.target.value)} />
            </div>
            <label style={S.lbl}>출현 빈도 <span style={{ color: '#94a3b8', fontWeight: 500 }}>· 이 풀이 나오는 빈도</span></label>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 10 }}>
              <input type="number" min="0" step="any" style={{ ...S.inp, width: 70 }} value={freqBoxes} onChange={e => setFreqBoxes(e.target.value)} />
              <span style={{ fontSize: 12, color: '#64748b', whiteSpace: 'nowrap' }}>박스당</span>
              <input type="number" min="0" step="any" style={{ ...S.inp, width: 60 }} value={freqCopies} onChange={e => setFreqCopies(e.target.value)} />
              <span style={{ fontSize: 12, color: '#64748b', whiteSpace: 'nowrap' }}>장</span>
            </div>
            <div style={{ marginBottom: 10 }}>
              <NumField label="풀 내 카드 수" value={poolSize} onChange={setPoolSize} step="1" suffix="종" disabled={weightMode !== 'equal'} />
            </div>
            <label style={S.lbl}>카드 선택 방식</label>
            <div style={{ display: 'flex', gap: 6, marginBottom: weightMode === 'manual' ? 10 : 0 }}>
              {wBtn('equal', poolSize > 0 ? `균등 가정 (1/${fmtNum(parseFloat(poolSize))})` : '균등 가정')}
              {wBtn('manual', '직접 확률 입력')}
            </div>
            {weightMode === 'manual' && (
              <NumField label={null} value={manualWeight} onChange={setManualWeight} suffix="%" hint="풀 안에서 이 카드 비중" />
            )}
          </div>

          {/* 팩 환산 조건 */}
          <label style={{ display: 'flex', alignItems: 'flex-start', gap: 8, marginBottom: 14, cursor: 'pointer' }}>
            <input type="checkbox" checked={packUniform} onChange={e => setPackUniform(e.target.checked)} style={{ marginTop: 2 }} />
            <span style={{ fontSize: 12, color: '#475569', lineHeight: 1.4 }}>
              박스 내 1장·팩 위치 균등 가정 <span style={{ color: '#94a3b8' }}>— 켜야 1팩/5팩 확률 산출 (p팩 = p박스 ÷ 팩수). 끄면 박스 단위부터 표시</span>
            </span>
          </label>

          {/* 갓팩 (선택) */}
          <div style={{ ...S.fieldset, background: godEnabled ? '#fffbeb' : '#fafbff', borderColor: godEnabled ? '#fde68a' : '#eef2f7' }}>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', marginBottom: godEnabled ? 12 : 0 }}>
              <input type="checkbox" checked={godEnabled} onChange={e => setGodEnabled(e.target.checked)} />
              <span style={{ fontSize: 12, fontWeight: 700, color: '#b45309' }}>갓팩 경로 포함 <span style={{ fontWeight: 500, color: '#94a3b8' }}>· 독립 경로 가정</span></span>
            </label>
            {godEnabled && (
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                <NumField label="갓팩 출현" value={godRateBoxes} onChange={setGodRateBoxes} step="1" suffix="박스당1" hint={null} />
                <NumField label="갓팩당 목표" value={godTargetProb} onChange={setGodTargetProb} suffix="%" hint={null} />
              </div>
            )}
          </div>

          {/* 가격 */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            <NumField label="박스 가격" value={boxPrice} onChange={setBoxPrice} suffix="원" />
            <NumField label="팩 가격" value={packPrice} onChange={setPackPrice} suffix="원" />
          </div>
          <div style={{ marginTop: 10 }}>
            <NumField label="카드 시세" hint={card?.koEstimatedPrice ? '검색 시 자동' : '본전 계산용'} value={cardPrice} onChange={setCardPrice} suffix="원" />
          </div>

          {calc && (
            <div style={{ marginTop: 14, padding: '10px 12px', borderRadius: 10, background: '#f8fafc', fontSize: 11, color: '#64748b', lineHeight: 1.6 }}>
              1박스 목표카드 확률 = {freqCopies}÷{freqBoxes}(풀 출현) × {calc.isEqual ? `1/${fmtNum(parseFloat(poolSize))}` : `${manualWeight}%`}(카드 비중){calc.pBoxGod > 0 ? ' + 갓팩(독립결합)' : ''} = <b style={{ color: '#4f46e5' }}>{fmtPct(calc.pBox)}</b>
            </div>
          )}
        </div>

        {/* ── 결과 ── */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          {!calc ? (
            <div style={{ ...S.card, textAlign: 'center', padding: '60px 20px', color: '#94a3b8', fontSize: 13 }}>
              출현 빈도 + 카드 풀을 입력하면 결과가 표시됩니다
            </div>
          ) : (
            <>
              {/* 요약 stat */}
              <div style={S.card}>
                <div style={S.section}>
                  {card ? cardName : '결과'}
                  {calc.isEqual && <span style={{ fontSize: 11, fontWeight: 600, color: '#c2410c', background: '#fff7ed', border: '1px solid #fed7aa', borderRadius: 99, padding: '2px 8px', marginLeft: 8 }}>균등 가정 추정치</span>}
                </div>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12 }}>
                  <StatBox accent label="1박스 확률" value={fmtPct(calc.pBox)} sub={`평균 ${fmtBoxes(calc.avgBoxes)}박스당 1장`} />
                  <StatBox label="50% 도달" value={isFinite(calc.box50) ? `${fmtNum(calc.box50)}박스` : '—'} sub="절반 확률" />
                  <StatBox label="90% 도달" value={isFinite(calc.box90) ? `${fmtNum(calc.box90)}박스` : '—'} sub="거의 확정" />
                  <StatBox label="기대 비용" value={calc.expectedCost ? fmtWon(calc.expectedCost) : '—'} sub={calc.boxPrice ? '첫 획득까지' : '박스 가격 입력 시'} />
                </div>
                {calc.breakevenBoxes && (
                  <div style={{ marginTop: 12, padding: '12px 14px', borderRadius: 10, background: 'linear-gradient(135deg,#f0fdf4,#ecfdf5)', border: '1px solid #bbf7d0' }}>
                    <span style={{ fontSize: 13, color: '#15803d', fontWeight: 700 }}>💰 카드값 기준 본전 {fmtNum(calc.breakevenBoxes)}박스</span>
                    <span style={{ fontSize: 13, color: '#166534', marginLeft: 8 }}>— 그 안에 뽑을 확률 <b>{fmtPct(calc.pBreakeven)}</b></span>
                    <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 3 }}>카드 {fmtWon(calc.cardPrice)} ÷ 박스 {fmtWon(calc.boxPrice)}</div>
                  </div>
                )}
              </div>

              {/* 구매 단위별 확률 */}
              <div style={S.card}>
                <div style={S.section}>구매 단위별 뽑을 확률 (최소 1장)
                  {calc.pPack == null && <span style={{ fontSize: 11, color: '#94a3b8', fontWeight: 500 }}> · 팩 단위는 균등 가정 꺼져 있어 산출 안 함</span>}
                </div>
                <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                  <thead>
                    <tr>
                      {['구매 단위', '확률', ...((calc.boxPrice || calc.packPrice) ? ['비용'] : [])].map(h => (
                        <th key={h} style={{ padding: '8px 12px', fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.6, textAlign: 'left', background: '#f8fafc', borderBottom: '1px solid #f1f5f9' }}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map(r => (
                      <tr key={r.key}>
                        <td style={{ padding: '10px 12px', fontSize: 13, color: '#475569', borderBottom: '1px solid #f8fafc' }}>{r.key}</td>
                        <td style={{ padding: '10px 12px', fontSize: 13, fontWeight: 700, color: '#4f46e5', borderBottom: '1px solid #f8fafc', fontVariantNumeric: 'tabular-nums' }}>
                          {fmtPct(r.prob)}
                          <div style={{ height: 4, borderRadius: 2, background: '#eef2ff', marginTop: 4, maxWidth: 200 }}>
                            <div style={{ height: '100%', borderRadius: 2, width: `${Math.min(100, r.prob * 100)}%`, background: 'linear-gradient(90deg,#6366f1,#4f46e5)' }} />
                          </div>
                        </td>
                        {(calc.boxPrice || calc.packPrice) && <td style={{ padding: '10px 12px', fontSize: 13, color: '#475569', borderBottom: '1px solid #f8fafc', fontVariantNumeric: 'tabular-nums' }}>{r.cost != null ? fmtWon(r.cost) : '—'}</td>}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* 차트 */}
              {chart.length > 1 && (
                <div style={S.card}>
                  <div style={S.section}>누적 확률 곡선 <span style={{ fontSize: 11, color: '#94a3b8', fontWeight: 500 }}>· 박스 단위</span></div>
                  <ResponsiveContainer width="100%" height={220}>
                    <LineChart data={chart} margin={{ top: 8, right: 16, left: -10, bottom: 0 }}>
                      <XAxis dataKey="n" type="number" domain={[0, 'dataMax']} tick={{ fontSize: 10, fill: '#94a3b8' }} axisLine={false} tickLine={false} tickFormatter={n => `${fmtNum(n)}박스`} />
                      <YAxis tick={{ fontSize: 10, fill: '#94a3b8' }} axisLine={false} tickLine={false} domain={[0, 100]} width={40} tickFormatter={v => `${v}%`} />
                      <Tooltip formatter={v => [`${v}%`, '최소 1장 확률']} labelFormatter={n => `${fmtNum(n)}박스 개봉`} contentStyle={{ borderRadius: 8, border: '1px solid #e2e8f0', fontSize: 11 }} />
                      {calc.breakevenBoxes <= (chart[chart.length - 1]?.n ?? 0) &&
                        <ReferenceLine x={calc.breakevenBoxes} stroke="#16a34a" strokeDasharray="4 4" label={{ value: '본전', fontSize: 10, fill: '#16a34a', position: 'top' }} />}
                      {isFinite(calc.box50) && calc.box50 <= (chart[chart.length - 1]?.n ?? 0) &&
                        <ReferenceLine x={calc.box50} stroke="#f59e0b" strokeDasharray="4 4" label={{ value: '50%', fontSize: 10, fill: '#f59e0b', position: 'top' }} />}
                      <Line type="monotone" dataKey="prob" stroke="#4f46e5" strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
                    </LineChart>
                  </ResponsiveContainer>
                </div>
              )}

              {/* 콘텐츠 복사 블록 */}
              <div style={S.card}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
                  <div style={S.section}>📸 콘텐츠 요약 <span style={{ fontSize: 11, color: '#94a3b8', fontWeight: 500 }}>· 게시물용 텍스트</span></div>
                  <button onClick={doCopy} style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '7px 14px', borderRadius: 8, border: 'none', cursor: 'pointer', background: copied ? '#16a34a' : 'linear-gradient(135deg,#6366f1,#4f46e5)', color: '#fff', fontSize: 12, fontWeight: 700, fontFamily: 'inherit' }}>
                    {copied ? <><Check size={14} /> 복사됨</> : <><Copy size={14} /> 복사</>}
                  </button>
                </div>
                <pre style={{ margin: 0, padding: '14px 16px', borderRadius: 10, background: '#f8fafc', border: '1px solid #f1f5f9', fontSize: 13, color: '#1e293b', lineHeight: 1.7, whiteSpace: 'pre-wrap', fontFamily: 'inherit' }}>{contentText}</pre>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
