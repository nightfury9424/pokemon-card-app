import { useEffect, useMemo, useRef, useState } from 'react'
import { Search, X, Calculator } from 'lucide-react'
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts'
import api from '../api'

const S = {
  page:   { padding: '32px 36px', minHeight: '100%', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' },
  h1:     { fontSize: 22, fontWeight: 700, color: '#1e293b', letterSpacing: -0.5 },
  sub:    { fontSize: 13, color: '#94a3b8', marginTop: 3 },
  card:   { background: '#fff', borderRadius: 16, border: '1px solid #e8edf4', boxShadow: '0 1px 3px rgba(0,0,0,0.04)', padding: 20 },
  lbl:    { fontSize: 11, fontWeight: 600, color: '#64748b', marginBottom: 4, display: 'block' },
  inp:    { width: '100%', boxSizing: 'border-box', padding: '9px 12px', borderRadius: 8, border: '1px solid #e2e8f0', fontSize: 13, color: '#1e293b', outline: 'none', fontFamily: 'inherit' },
  section:{ fontSize: 13, fontWeight: 700, color: '#1e293b', marginBottom: 12 },
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

// 카드 검색 → 선택 (라벨용 — 계산엔 봉입 수만 쓰임)
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

  // 바깥 클릭 시 드롭다운 닫기
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
        placeholder="카드 검색 (선택사항 — 라벨용)"
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
                <div style={{ fontSize: 10, color: '#94a3b8', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{c.setName ?? '-'}</div>
              </div>
              <RarityBadge rarity={c.rarity} />
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function NumField({ label, value, onChange, hint, min = 0, step = 'any', suffix }) {
  return (
    <div>
      <label style={S.lbl}>{label}{hint && <span style={{ color: '#94a3b8', fontWeight: 500 }}> · {hint}</span>}</label>
      <div style={{ position: 'relative' }}>
        <input type="number" min={min} step={step} style={{ ...S.inp, paddingRight: suffix ? 42 : 12 }} value={value}
          onChange={e => onChange(e.target.value)} />
        {suffix && <span style={{ position: 'absolute', right: 12, top: '50%', transform: 'translateY(-50%)', fontSize: 12, color: '#94a3b8' }}>{suffix}</span>}
      </div>
    </div>
  )
}

function StatBox({ label, value, sub, accent }) {
  return (
    <div style={{ padding: '14px 16px', borderRadius: 12, background: accent ? 'linear-gradient(135deg, #eef2ff, #f5f3ff)' : '#f8fafc', border: `1px solid ${accent ? '#c7d2fe' : '#f1f5f9'}` }}>
      <div style={{ fontSize: 11, fontWeight: 600, color: '#64748b' }}>{label}</div>
      <div style={{ fontSize: accent ? 26 : 19, fontWeight: 800, color: accent ? '#4f46e5' : '#1e293b', marginTop: 4, fontVariantNumeric: 'tabular-nums' }}>{value}</div>
      {sub && <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 3 }}>{sub}</div>}
    </div>
  )
}

export default function PullRate() {
  const [card, setCard] = useState(null)
  const [copiesPerCarton, setCopiesPerCarton] = useState('')   // 카톤당 봉입 수 (소수 허용: 0.5 = 2카톤당 1장)
  const [boxesPerCarton, setBoxesPerCarton] = useState('30')
  const [packsPerBox, setPacksPerBox] = useState('30')
  const [packPrice, setPackPrice] = useState('')
  const [customN, setCustomN] = useState('')

  const calc = useMemo(() => {
    const copies = parseFloat(copiesPerCarton)
    const boxes = parseFloat(boxesPerCarton)
    const packs = parseFloat(packsPerBox)
    if (!(copies > 0) || !(boxes > 0) || !(packs > 0)) return null
    const packsPerCarton = boxes * packs
    const p = Math.min(1, copies / packsPerCarton)     // 팩 1개에 대상 카드가 들어있을 확률
    const atLeastOne = (n) => 1 - Math.pow(1 - p, n)   // n팩 중 최소 1장 (무작위 혼합 가정 이항근사)
    const price = parseFloat(packPrice)
    return { p, packsPerCarton, atLeastOne, expectedPacks: 1 / p, price: price > 0 ? price : null }
  }, [copiesPerCarton, boxesPerCarton, packsPerBox, packPrice])

  // 대표 구간 테이블 — 팩/박스/카톤 단위 (중복 제거·정렬)
  const rows = useMemo(() => {
    if (!calc) return []
    const packs = parseFloat(packsPerBox)
    const defs = [
      { n: 1, label: '1팩' },
      { n: 5, label: '5팩' },
      { n: 10, label: '10팩' },
      { n: packs, label: `1박스 (${fmtNum(packs)}팩)` },
      { n: packs * 3, label: `3박스 (${fmtNum(packs * 3)}팩)` },
      { n: packs * 10, label: `10박스 (${fmtNum(packs * 10)}팩)` },
      { n: calc.packsPerCarton, label: `1카톤 (${fmtNum(calc.packsPerCarton)}팩)` },
    ]
    const seen = new Set()
    return defs.filter(d => d.n > 0 && !seen.has(d.n) && seen.add(d.n))
      .sort((a, b) => a.n - b.n)
      .map(d => ({ ...d, prob: calc.atLeastOne(d.n), cost: calc.price ? d.n * calc.price : null }))
  }, [calc, packsPerBox])

  // 누적 확률 곡선 — 99% 도달 지점까지 (최대 3카톤), ~60 포인트 샘플링
  const chart = useMemo(() => {
    if (!calc) return []
    const n99 = Math.log(0.01) / Math.log(1 - calc.p)
    const maxN = Math.ceil(Math.min(isFinite(n99) ? n99 : calc.packsPerCarton * 3, calc.packsPerCarton * 3))
    const step = Math.max(1, Math.floor(maxN / 60))
    const pts = []
    for (let n = 0; n <= maxN; n += step) pts.push({ n, prob: +(calc.atLeastOne(n) * 100).toFixed(2) })
    if (pts.length === 0 || pts[pts.length - 1].n < maxN) pts.push({ n: maxN, prob: +(calc.atLeastOne(maxN) * 100).toFixed(2) })
    return pts
  }, [calc])

  const customNum = parseFloat(customN)
  const customProb = calc && customNum > 0 ? calc.atLeastOne(customNum) : null

  return (
    <div style={S.page}>
      <div style={{ marginBottom: 24 }}>
        <div style={S.h1}>확률 계산기</div>
        <div style={S.sub}>봉입 수(카톤당)만 넣으면 팩 개봉 확률 계산 · 자판기/무작위 팩 가정</div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '340px 1fr', gap: 20, alignItems: 'start' }}>
        {/* ── 입력 ── */}
        <div style={S.card}>
          <div style={S.section}><Calculator size={14} style={{ verticalAlign: -2, marginRight: 6 }} />입력</div>

          <div style={{ marginBottom: 14 }}>
            <label style={S.lbl}>대상 카드</label>
            <CardPicker selected={card} onSelect={setCard} />
          </div>

          <div style={{ marginBottom: 14 }}>
            <NumField label="카톤당 봉입 수 *" hint="예: 카톤에 2장 → 2 · 2카톤에 1장 → 0.5"
              value={copiesPerCarton} onChange={setCopiesPerCarton} suffix="장" />
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginBottom: 14 }}>
            <NumField label="박스 / 카톤" value={boxesPerCarton} onChange={setBoxesPerCarton} step="1" suffix="박스" />
            <NumField label="팩 / 박스" value={packsPerBox} onChange={setPacksPerBox} step="1" suffix="팩" />
          </div>

          <div style={{ marginBottom: 4 }}>
            <NumField label="팩 가격" hint="선택 — 기대 비용 계산" value={packPrice} onChange={setPackPrice} suffix="원" />
          </div>

          {calc && (
            <div style={{ marginTop: 14, padding: '10px 12px', borderRadius: 10, background: '#f8fafc', fontSize: 11, color: '#64748b', lineHeight: 1.6 }}>
              카톤당 <b>{fmtNum(calc.packsPerCarton)}팩</b> · 팩당 확률 = {copiesPerCarton} ÷ {fmtNum(calc.packsPerCarton)}
              <div style={{ color: '#94a3b8', marginTop: 4 }}>
                ※ N팩 확률은 이항근사(팩 무작위 혼합). 같은 카톤을 통째로 개봉하면 봉입 수만큼 확정 획득.
              </div>
            </div>
          )}
        </div>

        {/* ── 결과 ── */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          {!calc ? (
            <div style={{ ...S.card, textAlign: 'center', padding: '60px 20px', color: '#94a3b8', fontSize: 13 }}>
              카톤당 봉입 수를 입력하면 결과가 표시됩니다
            </div>
          ) : (
            <>
              <div style={S.card}>
                <div style={S.section}>{card ? `${card.nameKo ?? card.nameEn} (${card.rarity})` : '결과'}</div>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12 }}>
                  <StatBox accent label="1팩 확률" value={fmtPct(calc.p)}
                    sub={calc.p > 0 && calc.p < 1 ? `약 ${fmtNum(1 / calc.p)}팩당 1장` : null} />
                  <StatBox label="기대 팩 수" value={`${fmtNum(calc.expectedPacks)}팩`}
                    sub={`≈ ${(calc.expectedPacks / calc.packsPerCarton * parseFloat(boxesPerCarton)).toFixed(1)}박스`} />
                  <StatBox label="기대 비용" value={calc.price ? fmtWon(calc.expectedPacks * calc.price) : '—'}
                    sub={calc.price ? `팩당 ${fmtWon(calc.price)}` : '팩 가격 입력 시 표시'} />
                </div>
              </div>

              <div style={S.card}>
                <div style={S.section}>N팩 개봉 시 최소 1장 확률</div>
                <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                  <thead>
                    <tr>
                      {['구매 단위', '확률', ...(calc.price ? ['비용'] : [])].map(h => (
                        <th key={h} style={{ padding: '8px 12px', fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.6, textAlign: 'left', background: '#f8fafc', borderBottom: '1px solid #f1f5f9' }}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map(r => (
                      <tr key={r.n}>
                        <td style={{ padding: '10px 12px', fontSize: 13, color: '#475569', borderBottom: '1px solid #f8fafc' }}>{r.label}</td>
                        <td style={{ padding: '10px 12px', fontSize: 13, fontWeight: 700, color: '#4f46e5', borderBottom: '1px solid #f8fafc', fontVariantNumeric: 'tabular-nums' }}>
                          {fmtPct(r.prob)}
                          <div style={{ height: 4, borderRadius: 2, background: '#eef2ff', marginTop: 4, maxWidth: 200 }}>
                            <div style={{ height: '100%', borderRadius: 2, width: `${Math.min(100, r.prob * 100)}%`, background: 'linear-gradient(90deg,#6366f1,#4f46e5)' }} />
                          </div>
                        </td>
                        {calc.price && <td style={{ padding: '10px 12px', fontSize: 13, color: '#475569', borderBottom: '1px solid #f8fafc', fontVariantNumeric: 'tabular-nums' }}>{fmtWon(r.cost)}</td>}
                      </tr>
                    ))}
                    {/* 직접 입력 행 */}
                    <tr>
                      <td style={{ padding: '10px 12px', borderBottom: 'none' }}>
                        <input type="number" min="1" placeholder="직접 입력 (팩)" value={customN} onChange={e => setCustomN(e.target.value)}
                          style={{ ...S.inp, width: 130, padding: '6px 10px', fontSize: 12 }} />
                      </td>
                      <td style={{ padding: '10px 12px', fontSize: 13, fontWeight: 700, color: '#4f46e5', borderBottom: 'none', fontVariantNumeric: 'tabular-nums' }}>
                        {customProb != null ? fmtPct(customProb) : '—'}
                      </td>
                      {calc.price && <td style={{ padding: '10px 12px', fontSize: 13, color: '#475569', borderBottom: 'none', fontVariantNumeric: 'tabular-nums' }}>{customNum > 0 ? fmtWon(customNum * calc.price) : '—'}</td>}
                    </tr>
                  </tbody>
                </table>
              </div>

              {chart.length > 1 && (
                <div style={S.card}>
                  <div style={S.section}>누적 확률 곡선 <span style={{ fontSize: 11, color: '#94a3b8', fontWeight: 500 }}>· 99% 도달까지 (최대 3카톤)</span></div>
                  <ResponsiveContainer width="100%" height={220}>
                    <LineChart data={chart} margin={{ top: 8, right: 16, left: -10, bottom: 0 }}>
                      {/* type=number 필수 — categorical 축이면 ReferenceLine(1카톤)이 샘플점과 안 맞을 때 미표시 */}
                      <XAxis dataKey="n" type="number" domain={[0, 'dataMax']} tick={{ fontSize: 10, fill: '#94a3b8' }} axisLine={false} tickLine={false}
                        tickFormatter={n => `${fmtNum(n)}팩`} />
                      <YAxis tick={{ fontSize: 10, fill: '#94a3b8' }} axisLine={false} tickLine={false} domain={[0, 100]} width={40}
                        tickFormatter={v => `${v}%`} />
                      <Tooltip formatter={v => [`${v}%`, '최소 1장 확률']} labelFormatter={n => `${fmtNum(n)}팩 개봉`}
                        contentStyle={{ borderRadius: 8, border: '1px solid #e2e8f0', fontSize: 11 }} />
                      <ReferenceLine x={calc.packsPerCarton} stroke="#f59e0b" strokeDasharray="4 4"
                        label={{ value: '1카톤', fontSize: 10, fill: '#f59e0b', position: 'top' }} />
                      <Line type="monotone" dataKey="prob" stroke="#4f46e5" strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
                    </LineChart>
                  </ResponsiveContainer>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}
