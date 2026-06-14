import { useEffect, useState, useCallback, useRef } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { Search, Plus, ChevronLeft, ChevronRight, X } from 'lucide-react'
import api from '../api'

const S = {
  page:   { padding: '32px 36px', minHeight: '100%', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' },
  header: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 },
  h1:     { fontSize: 22, fontWeight: 700, color: '#1e293b', letterSpacing: -0.5 },
  sub:    { fontSize: 13, color: '#94a3b8', marginTop: 3 },
  card:   { background: '#fff', borderRadius: 16, border: '1px solid #e8edf4', boxShadow: '0 1px 3px rgba(0,0,0,0.04)', overflow: 'hidden' },
  th:     { padding: '12px 16px', fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.6, textAlign: 'left', background: '#f8fafc', borderBottom: '1px solid #f1f5f9' },
  td:     { padding: '13px 16px', fontSize: 13, color: '#475569', borderBottom: '1px solid #f8fafc' },
}

const RARITIES = ['전체', 'SSR', 'SAR', 'BWR', 'CSR', 'CHR', 'MUR', 'UR', 'SR', 'AR', 'ACE', 'RRR', 'RR', 'HR', 'PR']
const RARITY_OPTIONS = ['SSR', 'SAR', 'BWR', 'CSR', 'CHR', 'MUR', 'UR', 'SR', 'AR', 'ACE', 'RRR', 'RR', 'HR', 'PR']

// ── B1(문의→폼 prefill) 유틸 ──
// 문의 레어도는 자유입력 → 셀렉트 옵션과 정확히 일치할 때만 채움(아니면 admin 수동선택, Codex 원칙)
const normalizeRarity = (r) => {
  const up = (r || '').trim().toUpperCase()
  return RARITY_OPTIONS.includes(up) ? up : ''
}
// 참고 링크에서 조회코드 추출: pokemoncard…/detail/BS… · scrydex…/_/smp_ja-407 → 마지막 path 세그먼트
const extractLookupCode = (link) => {
  if (!link) return ''
  const seg = link.split('?')[0].replace(/\/+$/, '').split('/').pop() || ''
  return /^[A-Za-z0-9_\-]{3,40}$/.test(seg) ? seg : ''
}

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

function AddCardModal({ onClose, onAdded, prefill }) {
  // ── 3판본(KO/JP/EN) 각각 조회 상태 ──
  const mkCol = (code = '') => ({ code, looking: false, err: '', looked: false, name: '', rarity: '', num: '', img: '', productName: '', productId: '' })
  const pfCode = prefill ? (extractLookupCode(prefill.refLink) || '') : ''
  const [ko, setKo] = useState(() => mkCol(prefill?.language === 'KO' ? pfCode : ''))
  const [jp, setJp] = useState(() => mkCol(prefill?.language === 'JP' ? pfCode : ''))
  const [en, setEn] = useState(() => mkCol(prefill?.language === 'EN' ? pfCode : ''))
  const cols = { KO: [ko, setKo], JP: [jp, setJp], EN: [en, setEn] }

  // ── 공용(생성할 카드) ──
  const [name, setName] = useState(prefill?.name || '')
  const [rarityCode, setRarityCode] = useState(prefill ? normalizeRarity(prefill.rarity) : '')
  const [productId, setProductId] = useState('')
  const [productSearch, setProductSearch] = useState(prefill?.setName || '')
  const [products, setProducts] = useState([])

  // ── 시세 (preview dry-run) ──
  const [prices, setPrices] = useState(null)   // {koEstimated, jpRawKrw, enRawKrw, isChaseCandidate}

  // ── 제출 ──
  const [submitting, setSubmitting] = useState(false)
  const [submitErr, setSubmitErr] = useState('')

  const won = (n) => (n == null ? '—' : Number(n).toLocaleString('ko-KR') + '원')

  // 세트 목록
  useEffect(() => {
    api.get('/admin/products', { params: { search: productSearch || undefined } })
      .then(r => setProducts(r.data?.data ?? [])).catch(() => setProducts([]))
  }, [productSearch])

  // 시세 갱신 — 레어도/세트/JP·EN ref 바뀌면 (디바운스). KO=모델, JP/EN=실시장가 백필.
  useEffect(() => {
    if (!rarityCode) { setPrices(null); return }
    const t = setTimeout(() => {
      api.post('/admin/cards/preview', {
        rarityCode, productId: productId || null,
        jpScrydexRef: jp.code.trim() || null, enScrydexRef: en.code.trim() || null,
      }).then(r => setPrices(r.data?.data ?? null)).catch(() => setPrices(null))
    }, 400)
    return () => clearTimeout(t)
  }, [rarityCode, productId, jp.code, en.code])

  // 판본별 조회 — URL 통째로 붙여도 ref 자동추출
  const lookup = async (ed) => {
    const [col, set] = cols[ed]
    const raw = col.code.trim()
    if (!raw) return
    const code = extractLookupCode(raw) || raw
    set(c => ({ ...c, code, looking: true, err: '', looked: false }))
    try {
      const r = await api.get('/admin/cards/lookup', { params: { type: ed, code } })
      const d = r.data?.data ?? {}
      set(c => ({ ...c, looking: false, looked: true, name: d.name || '', rarity: d.rarityCode || '', num: d.collectionNumber || '', img: d.imageUrl || '', productName: d.productName || '', productId: d.productId || '' }))
      if (ed === 'KO') {   // KO 조회 → 공용 필드 자동 채움
        if (d.name) setName(d.name)
        if (d.rarityCode) setRarityCode(normalizeRarity(d.rarityCode) || d.rarityCode)
        if (d.productId) setProductId(d.productId)
        if (d.productName) setProductSearch(d.productName)
      }
    } catch (e) {
      set(c => ({ ...c, looking: false, err: e.response?.data?.message ?? '조회 실패' }))
    }
  }

  const handleSubmit = async () => {
    if (!name.trim())  return setSubmitErr('카드명(KO)을 입력하세요.')
    if (!rarityCode)   return setSubmitErr('레어도를 선택하세요.')
    const koCode = ko.code.trim(), jpRef = jp.code.trim(), enRef = en.code.trim()
    if (!koCode && !jpRef && !enRef) return setSubmitErr('최소 한 판본의 코드를 조회하세요.')
    const type = koCode ? 'KO' : jpRef ? 'JP' : 'EN'   // KO 있으면 KO카드(+ref연결), 없으면 단독
    if (type === 'KO' && !productId) return setSubmitErr('세트를 선택하세요.')
    const body = {
      type, name: name.trim(), productId: productId || null, rarityCode,
      collectionNumber: ko.num || jp.num || en.num || null,
      officialCardCode: koCode || null,
      jpScrydexRef: jpRef || null,
      enScrydexRef: enRef || null,
    }
    setSubmitting(true); setSubmitErr('')
    try { await api.post('/admin/cards', body); onAdded(); onClose() }
    catch (e) { setSubmitErr(e.response?.data?.message ?? '추가 실패'); setSubmitting(false) }
  }

  const META = {
    KO: { flag: '🇰🇷', hint: 'BS2023014205 · 코리아 URL', priceLabel: '예상가(모델)',  price: () => prices?.koEstimated },
    JP: { flag: '🇯🇵', hint: 'm3_ja-117 · scrydex URL',   priceLabel: 'JP 실시세(백필)', price: () => prices?.jpRawKrw },
    EN: { flag: '🇺🇸', hint: 'swsh8-269 · scrydex URL',   priceLabel: 'EN 실시세(백필)', price: () => prices?.enRawKrw },
  }

  const inp = { width: '100%', padding: '8px 10px', borderRadius: 8, border: '1px solid #e2e8f0', fontSize: 12, color: '#1e293b', outline: 'none', fontFamily: 'inherit', boxSizing: 'border-box' }
  const lbl = { fontSize: 11, fontWeight: 600, color: '#64748b', marginBottom: 4, display: 'block' }

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.45)', zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}
      onClick={e => e.target === e.currentTarget && onClose()}>
      <div style={{ background: '#fff', borderRadius: 16, width: 920, maxWidth: '95vw', maxHeight: '92vh', overflow: 'auto', boxShadow: '0 20px 60px rgba(0,0,0,0.18)' }}>

        {/* 헤더 */}
        <div style={{ padding: '20px 24px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ fontSize: 16, fontWeight: 700, color: '#1e293b' }}>카드 추가 <span style={{ fontSize: 12, color: '#94a3b8', fontWeight: 500 }}>· KO·JP·EN 한 번에</span></span>
          <button onClick={onClose} style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#94a3b8', padding: 4 }}><X size={18} /></button>
        </div>

        {/* 3판본 컬럼 */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 12, padding: '16px 24px' }}>
          {['KO', 'JP', 'EN'].map(ed => {
            const [col] = cols[ed]; const m = META[ed]; const price = m.price()
            return (
              <div key={ed} style={{ border: '1px solid #eef2f7', borderRadius: 12, padding: 12, background: '#fafbff' }}>
                <div style={{ fontSize: 13, fontWeight: 700, color: '#1e293b', marginBottom: 8 }}>{m.flag} {ed}</div>
                <div style={{ display: 'flex', gap: 6 }}>
                  <input style={{ ...inp, flex: 1 }} placeholder={m.hint} value={col.code}
                    onChange={e => cols[ed][1](c => ({ ...c, code: e.target.value, looked: false }))}
                    onKeyDown={e => e.key === 'Enter' && lookup(ed)} />
                  <button onClick={() => lookup(ed)} disabled={col.looking} style={{ padding: '8px 12px', borderRadius: 8, border: 'none', cursor: col.looking ? 'wait' : 'pointer', background: col.looking ? '#e2e8f0' : '#6366f1', color: col.looking ? '#94a3b8' : '#fff', fontSize: 12, fontWeight: 600, fontFamily: 'inherit', whiteSpace: 'nowrap' }}>{col.looking ? '...' : '조회'}</button>
                </div>
                {col.err && <div style={{ color: '#dc2626', fontSize: 11, marginTop: 6 }}>{col.err}</div>}
                {col.looked && (
                  <div style={{ marginTop: 10 }}>
                    {col.img && <img src={col.img} alt={ed} onError={e => { e.currentTarget.style.display = 'none' }} style={{ width: '100%', borderRadius: 8, marginBottom: 8, boxShadow: '0 1px 6px rgba(0,0,0,0.12)' }} />}
                    <div style={{ fontSize: 12, fontWeight: 600, color: '#1e293b' }}>{col.name || '—'}</div>
                    <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 2 }}>{[col.rarity, col.num].filter(Boolean).join(' · ') || '—'}</div>
                    <div style={{ fontSize: 14, fontWeight: 800, color: '#4f46e5', marginTop: 6 }}>
                      {won(price)} <span style={{ fontSize: 9, fontWeight: 600, color: '#94a3b8' }}>{m.priceLabel}</span>
                    </div>
                    {ed === 'KO' && prices?.isChaseCandidate && <div style={{ fontSize: 9, color: '#c2410c', marginTop: 2 }}>⚠ 익일 배치 후 조정 가능</div>}
                  </div>
                )}
              </div>
            )
          })}
        </div>

        {/* 공용 필드 (생성할 카드) */}
        <div style={{ display: 'grid', gridTemplateColumns: '2fr 2fr 1fr', gap: 12, padding: '0 24px 8px', alignItems: 'start' }}>
          <div><label style={lbl}>카드명 (KO) *</label><input style={inp} value={name} onChange={e => setName(e.target.value)} placeholder="카드명" /></div>
          <div>
            <label style={lbl}>세트 *</label>
            <input style={{ ...inp, marginBottom: 4 }} placeholder="세트 검색..." value={productSearch} onChange={e => setProductSearch(e.target.value)} />
            <select style={{ ...inp, background: '#fff' }} value={productId} onChange={e => setProductId(e.target.value)}>
              <option value="">-- 선택 --</option>
              {products.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </div>
          <div>
            <label style={lbl}>레어도 *</label>
            <select style={{ ...inp, background: '#fff' }} value={rarityCode} onChange={e => setRarityCode(e.target.value)}>
              <option value="">선택</option>
              {RARITY_OPTIONS.map(r => <option key={r} value={r}>{r}</option>)}
            </select>
          </div>
        </div>

        {submitErr && <div style={{ margin: '4px 24px', padding: '8px 12px', background: '#fef2f2', borderRadius: 8, color: '#dc2626', fontSize: 12 }}>{submitErr}</div>}

        {/* 푸터 */}
        <div style={{ padding: '12px 24px 20px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12 }}>
          <span style={{ fontSize: 11, color: '#94a3b8', lineHeight: 1.4 }}>KO 코드 있으면 KO 카드(+JP/EN ref 연결) · KO 없이 JP/EN만이면 단독 추가</span>
          <div style={{ display: 'flex', gap: 8, flexShrink: 0 }}>
            <button onClick={onClose} style={{ padding: '9px 18px', borderRadius: 10, border: '1px solid #e2e8f0', background: '#fff', color: '#64748b', fontSize: 13, fontWeight: 600, cursor: 'pointer', fontFamily: 'inherit' }}>취소</button>
            <button onClick={handleSubmit} disabled={submitting} style={{ padding: '9px 18px', borderRadius: 10, border: 'none', background: submitting ? '#a5b4fc' : 'linear-gradient(135deg, #6366f1 0%, #4f46e5 100%)', color: '#fff', fontSize: 13, fontWeight: 600, cursor: submitting ? 'not-allowed' : 'pointer', fontFamily: 'inherit' }}>{submitting ? '추가 중...' : '카드 추가'}</button>
          </div>
        </div>
      </div>
    </div>
  )
}

// ── A: 시리즈(세트) 일괄추가 모달 (KO, pokemoncard 순차 walk) ──
function BulkAddModal({ onClose, onAdded }) {
  const [input, setInput] = useState('')
  const [previewing, setPreviewing] = useState(false)
  const [preview, setPreview] = useState(null)       // {prefix,found,existing,newCount,cards}
  const [selected, setSelected] = useState({})       // {officialCardCode: bool}
  const [productId, setProductId] = useState('')
  const [productSearch, setProductSearch] = useState('')
  const [products, setProducts] = useState([])
  const [inserting, setInserting] = useState(false)
  const [result, setResult] = useState(null)
  const [err, setErr] = useState('')

  useEffect(() => {
    api.get('/admin/products', { params: { search: productSearch || undefined } })
      .then(r => setProducts(r.data?.data ?? []))
      .catch(() => setProducts([]))
  }, [productSearch])

  // 입력에서 prefix(영문2+숫자7) 추출 — 카드코드(BS2026003001)·URL 붙여도 OK
  const derivePrefix = (s) => {
    const m = (s || '').match(/([A-Za-z]{2}\d{7})/)
    return m ? m[1] : ''
  }

  const ui = {
    inp: { width: '100%', boxSizing: 'border-box', padding: '9px 12px', borderRadius: 8, border: '1px solid #e2e8f0', fontSize: 13, fontFamily: 'inherit' },
    lbl: { fontSize: 12, fontWeight: 600, color: '#64748b', marginBottom: 4, display: 'block' },
    btn: (on) => ({ padding: '9px 16px', borderRadius: 8, border: 'none', cursor: on ? 'not-allowed' : 'pointer', background: on ? '#e2e8f0' : '#6366f1', color: on ? '#94a3b8' : '#fff', fontSize: 13, fontWeight: 600, fontFamily: 'inherit', whiteSpace: 'nowrap' }),
  }

  async function runPreview() {
    const prefix = derivePrefix(input)
    if (!prefix) { setErr('세트 prefix(예: BS2026003) 또는 카드코드/URL을 입력하세요.'); return }
    setPreviewing(true); setErr(''); setPreview(null); setResult(null)
    try {
      const r = await api.get('/admin/cards/bulk-preview', { params: { prefix } })
      const d = r.data?.data
      setPreview(d)
      const sel = {}; let seedSet = '', seedName = ''
      for (const c of d.cards) {
        // 기본 선택 = 신규 & chase(저레어 아님)만. 저레어는 정책상 제외 → admin이 원하면 수동 체크
        if (!c.exists && !c.lowRarity) { sel[c.officialCardCode] = true; if (!seedSet && c.productId) seedSet = c.productId }
        if (!seedName && c.productName) seedName = c.productName
      }
      setSelected(sel)
      if (seedSet) setProductId(seedSet)
      if (seedName) setProductSearch(seedName)
    } catch (e) {
      setErr(e.response?.data?.message || '미리보기 실패')
    } finally { setPreviewing(false) }
  }

  async function runInsert() {
    if (!productId) { setErr('추가할 세트를 선택하세요.'); return }
    const cards = (preview?.cards || []).filter(c => !c.exists && selected[c.officialCardCode])
    if (cards.length === 0) { setErr('추가할 카드를 선택하세요.'); return }
    const allowLowRarity = cards.some(c => c.lowRarity)  // admin이 저레어를 명시 선택했으면 override
    setInserting(true); setErr('')
    try {
      const r = await api.post('/admin/cards/bulk-insert', { productId, cards, allowLowRarity })
      setResult(r.data?.data)
      onAdded?.()
    } catch (e) {
      setErr(e.response?.data?.message || '추가 실패')
    } finally { setInserting(false) }
  }

  const newCards  = (preview?.cards || []).filter(c => !c.exists)
  const keepCards = newCards.filter(c => !c.lowRarity)        // chase (정책 노출)
  const lowCount  = newCards.length - keepCards.length        // 저레어(C/U/R/S/K·미상)
  const selCount  = newCards.filter(c => selected[c.officialCardCode]).length
  const allKeepSel = keepCards.length > 0 && keepCards.every(c => selected[c.officialCardCode])
  const toggleAll = () => {
    const next = { ...selected }   // 저레어 수동선택은 보존, chase만 토글
    keepCards.forEach(c => { if (allKeepSel) delete next[c.officialCardCode]; else next[c.officialCardCode] = true })
    setSelected(next)
  }

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.45)', zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}
      onClick={e => e.target === e.currentTarget && onClose()}>
      <div style={{ background: '#fff', borderRadius: 16, width: 620, maxHeight: '90vh', overflow: 'auto', boxShadow: '0 20px 60px rgba(0,0,0,0.18)' }}>
        <div style={{ padding: '20px 24px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ fontSize: 16, fontWeight: 700, color: '#1e293b' }}>시리즈 일괄추가 <span style={{ fontSize: 12, color: '#94a3b8', fontWeight: 500 }}>· KO (포켓몬코리아)</span></span>
          <button onClick={onClose} style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#94a3b8', padding: 4 }}><X size={18} /></button>
        </div>

        <div style={{ padding: '20px 24px' }}>
          {/* STEP 1: prefix 입력 */}
          <label style={ui.lbl}>세트 prefix 또는 카드코드/URL *</label>
          <div style={{ display: 'flex', gap: 8 }}>
            <input style={{ ...ui.inp, flex: 1 }} placeholder="예: BS2026003  ·  BS2026003001  ·  pokemoncard URL"
              value={input} onChange={e => setInput(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && runPreview()} />
            <button onClick={runPreview} disabled={previewing} style={ui.btn(previewing)}>{previewing ? '조회 중...' : '미리보기'}</button>
          </div>
          <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 6 }}>
            코드 구조 BS+연도4+세트번호3 (+카드번호3). 1번부터 빈 카드 연속까지 자동 수집 → 기존 카드는 자동 제외.
          </div>

          {err && <div style={{ marginTop: 12, padding: '8px 12px', background: '#fef2f2', borderRadius: 8, color: '#dc2626', fontSize: 12 }}>{err}</div>}

          {/* STEP 2: 미리보기 결과 */}
          {preview && (
            <>
              <div style={{ height: 1, background: '#f1f5f9', margin: '16px 0' }} />
              <div style={{ fontSize: 13, color: '#475569', marginBottom: 12 }}>
                <b>{preview.found}</b>장 발견 · 신규 chase <b style={{ color: '#4f46e5' }}>{keepCards.length}</b> · 기존 {preview.existing}
                {lowCount > 0 && <span style={{ color: '#dc2626' }}> · 저레어 {lowCount} 제외</span>}
              </div>

              {/* 세트 선택 (일괄 적용) */}
              <label style={ui.lbl}>추가할 세트 (전체 일괄 적용) *</label>
              <input style={{ ...ui.inp, marginBottom: 6 }} placeholder="세트 검색..."
                value={productSearch} onChange={e => setProductSearch(e.target.value)} />
              <select style={{ ...ui.inp, background: '#fff', marginBottom: 14 }} size={3} value={productId}
                onChange={e => setProductId(e.target.value)}>
                <option value="">-- 선택 --</option>
                {products.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
              </select>

              {/* 카드 목록 */}
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
                <label style={{ fontSize: 12, fontWeight: 600, color: '#64748b', cursor: 'pointer' }}>
                  <input type="checkbox" checked={allKeepSel} onChange={toggleAll} style={{ marginRight: 6 }} />
                  chase 신규 전체선택 ({keepCards.filter(c => selected[c.officialCardCode]).length}/{keepCards.length})
                </label>
                {lowCount > 0 && <span style={{ fontSize: 11, color: '#dc2626' }}>저레어 {lowCount}장은 정책상 기본 제외 (수동 체크 시 추가)</span>}
              </div>
              <div style={{ maxHeight: 240, overflow: 'auto', border: '1px solid #f1f5f9', borderRadius: 8 }}>
                {preview.cards.map(c => (
                  <div key={c.officialCardCode} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '7px 12px', borderBottom: '1px solid #f8fafc', fontSize: 12, opacity: c.exists ? 0.4 : (c.lowRarity ? 0.6 : 1) }}>
                    <input type="checkbox" disabled={c.exists} checked={!!selected[c.officialCardCode]}
                      onChange={e => setSelected(s => ({ ...s, [c.officialCardCode]: e.target.checked }))} />
                    <span style={{ fontFamily: 'monospace', color: '#94a3b8', minWidth: 96 }}>{c.officialCardCode}</span>
                    <span style={{ flex: 1, color: '#1e293b', fontWeight: 600 }}>{c.name || '(이름없음)'}</span>
                    <span style={{ minWidth: 42, color: c.rarityCode ? '#475569' : '#dc2626' }}>{c.rarityCode || '레어도?'}</span>
                    <span style={{ minWidth: 56, color: '#94a3b8' }}>{c.collectionNumber || '-'}</span>
                    {c.exists ? <span style={{ fontSize: 10, color: '#16a34a', fontWeight: 700, minWidth: 42, textAlign: 'right' }}>기존</span>
                      : c.lowRarity ? <span style={{ fontSize: 10, color: '#dc2626', fontWeight: 700, minWidth: 42, textAlign: 'right' }}>저레어</span>
                      : <span style={{ minWidth: 42 }} />}
                  </div>
                ))}
              </div>

              {result ? (
                <div style={{ marginTop: 14, padding: '10px 14px', background: '#f0fdf4', borderRadius: 8, color: '#15803d', fontSize: 13 }}>
                  ✓ {result.inserted}장 추가 · {result.skipped} skip{result.errors?.length ? ` · 오류 ${result.errors.length}` : ''}
                  {result.errors?.length ? <div style={{ fontSize: 11, color: '#b45309', marginTop: 4 }}>{result.errors.join(', ')}</div> : null}
                </div>
              ) : (
                <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end', marginTop: 16 }}>
                  <button onClick={onClose} style={{ padding: '9px 18px', borderRadius: 10, border: '1px solid #e2e8f0', background: '#fff', color: '#64748b', fontSize: 13, fontWeight: 600, cursor: 'pointer' }}>닫기</button>
                  <button onClick={runInsert} disabled={inserting || selCount === 0 || !productId}
                    style={{ padding: '9px 18px', borderRadius: 10, border: 'none', background: (inserting || selCount === 0 || !productId) ? '#a5b4fc' : 'linear-gradient(135deg, #6366f1 0%, #4f46e5 100%)', color: '#fff', fontSize: 13, fontWeight: 600, cursor: (inserting || selCount === 0 || !productId) ? 'not-allowed' : 'pointer' }}>
                    {inserting ? '추가 중...' : `선택 ${selCount}장 추가`}
                  </button>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}

export default function Cards() {
  const location = useLocation()
  const navigate = useNavigate()
  const [cards, setCards] = useState([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(0)
  const [search, setSearch] = useState('')
  const [rarity, setRarity] = useState('전체')
  const [loading, setLoading] = useState(true)
  const [showAdd, setShowAdd] = useState(false)
  const [showBulk, setShowBulk] = useState(false)
  const [prefill, setPrefill] = useState(null)   // 문의(카드추가요청)에서 넘어온 prefill
  const size = 15

  // 문의 → "카드 추가하기"로 진입 시 모달 자동 오픈 + prefill, state는 즉시 소거(새로고침/뒤로가기 재오픈 방지)
  const handledKey = useRef(null)
  useEffect(() => {
    const pf = location.state?.prefillCard
    if (pf && handledKey.current !== location.key) {  // 같은 history 엔트리 재진입(뒤로가기) 차단
      handledKey.current = location.key
      setPrefill(pf)
      setShowAdd(true)
      navigate(location.pathname, { replace: true, state: null })
    }
  }, [location.state, location.key, location.pathname, navigate])

  const load = useCallback(() => {
    setLoading(true)
    api.get('/admin/cards', {
      params: {
        page, size,
        search: search || undefined,
        rarity: rarity === '전체' ? undefined : rarity,
      }
    })
      .then(r => {
        setCards(r.data?.data?.content ?? [])
        setTotal(r.data?.data?.totalElements ?? 0)
      })
      .catch(() => { setCards([]); setTotal(0) })
      .finally(() => setLoading(false))
  }, [page, search, rarity])

  useEffect(() => { load() }, [load])

  const totalPages = Math.ceil(total / size)

  return (
    <div style={S.page}>
      {showAdd && <AddCardModal prefill={prefill}
        onClose={() => { setShowAdd(false); setPrefill(null) }} onAdded={load} />}
      {showBulk && <BulkAddModal onClose={() => setShowBulk(false)} onAdded={load} />}

      <div style={S.header}>
        <div>
          <div style={S.h1}>카드 관리</div>
          <div style={S.sub}>총 {total.toLocaleString()}장의 카드 (KO 기준)</div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button onClick={() => setShowBulk(true)} style={{
            display: 'flex', alignItems: 'center', gap: 6,
            padding: '9px 16px', borderRadius: 10, border: '1px solid #c7d2fe', cursor: 'pointer',
            background: '#eef2ff', color: '#4f46e5', fontSize: 13, fontWeight: 600, fontFamily: 'inherit',
          }}>
            <Plus size={14} />
            시리즈 일괄추가
          </button>
          <button onClick={() => setShowAdd(true)} style={{
            display: 'flex', alignItems: 'center', gap: 6,
            padding: '9px 18px', borderRadius: 10, border: 'none', cursor: 'pointer',
            background: 'linear-gradient(135deg, #6366f1 0%, #4f46e5 100%)',
            color: '#fff', fontSize: 13, fontWeight: 600, fontFamily: 'inherit',
          }}>
            <Plus size={14} />
            카드 추가
          </button>
        </div>
      </div>

      {/* 검색 + 희귀도 필터 */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 16 }}>
        <div style={{ position: 'relative', width: 280 }}>
          <Search size={14} style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', color: '#94a3b8' }} />
          <input
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(0) }}
            placeholder="카드명 검색 (KO/EN/JP)"
            style={{
              width: '100%', padding: '9px 12px 9px 34px', borderRadius: 10,
              border: '1px solid #e2e8f0', background: '#fff', fontSize: 13,
              color: '#1e293b', outline: 'none', fontFamily: 'inherit',
            }}
          />
        </div>
        <div style={{ display: 'flex', gap: 6 }}>
          {RARITIES.map(r => (
            <button key={r} onClick={() => { setRarity(r); setPage(0) }} style={{
              padding: '7px 12px', borderRadius: 99, border: '1px solid',
              fontSize: 12, cursor: 'pointer', fontFamily: 'inherit', transition: 'all 0.1s',
              background: rarity === r ? '#6366f1' : '#fff',
              color: rarity === r ? '#fff' : '#64748b',
              borderColor: rarity === r ? '#6366f1' : '#e2e8f0',
              fontWeight: rarity === r ? 600 : 400,
            }}>{r}</button>
          ))}
        </div>
      </div>

      <div style={S.card}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              {['카드 ID', '이름 (KO)', '이름 (EN)', '세트', '희귀도', '스캔수', '시세(KO)'].map(h => (
                <th key={h} style={S.th}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={7} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>불러오는 중...</td></tr>
            ) : cards.length === 0 ? (
              <tr><td colSpan={7} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>카드가 없습니다</td></tr>
            ) : cards.map(c => (
              <tr key={c.id}
                onMouseEnter={e => e.currentTarget.style.background = '#fafafa'}
                onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
              >
                <td style={{ ...S.td, color: '#94a3b8', fontSize: 12, fontFamily: 'monospace' }}>{c.id}</td>
                <td style={{ ...S.td, fontWeight: 600, color: '#1e293b' }}>{c.nameKo ?? '-'}</td>
                <td style={S.td}>{c.nameEn ?? '-'}</td>
                <td style={{ ...S.td, fontSize: 12 }}>{c.setName ?? '-'}</td>
                <td style={S.td}><RarityBadge rarity={c.rarity} /></td>
                <td style={S.td}>{(c.scanCount ?? 0).toLocaleString()}</td>
                <td style={{ ...S.td, fontWeight: 600, color: '#1e293b' }}>
                  {c.koEstimatedPrice ? `${c.koEstimatedPrice.toLocaleString()}원` : '-'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {totalPages > 1 && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 8, padding: '12px 16px', borderTop: '1px solid #f1f5f9' }}>
            <button onClick={() => setPage(p => Math.max(0, p - 1))} disabled={page === 0}
              style={{ padding: '5px', border: '1px solid #e2e8f0', borderRadius: 8, background: '#fff', cursor: page === 0 ? 'not-allowed' : 'pointer', opacity: page === 0 ? 0.4 : 1 }}>
              <ChevronLeft size={15} color="#64748b" />
            </button>
            <span style={{ fontSize: 13, color: '#64748b' }}>{page + 1} / {totalPages}</span>
            <button onClick={() => setPage(p => Math.min(totalPages - 1, p + 1))} disabled={page >= totalPages - 1}
              style={{ padding: '5px', border: '1px solid #e2e8f0', borderRadius: 8, background: '#fff', cursor: page >= totalPages - 1 ? 'not-allowed' : 'pointer', opacity: page >= totalPages - 1 ? 0.4 : 1 }}>
              <ChevronRight size={15} color="#64748b" />
            </button>
          </div>
        )}
      </div>
    </div>
  )
}
