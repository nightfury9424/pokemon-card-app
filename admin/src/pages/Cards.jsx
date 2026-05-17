import { useEffect, useState, useCallback } from 'react'
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

const RARITIES = ['전체', 'SSR', 'SAR', 'BWR', 'CSR', 'CHR', 'UR', 'SR', 'AR', 'ACE', 'RRR', 'RR', 'HR', 'PR']
const RARITY_OPTIONS = ['SSR', 'SAR', 'BWR', 'CSR', 'CHR', 'MUR', 'UR', 'SR', 'AR', 'ACE', 'RRR', 'RR', 'HR', 'PR']

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

function AddCardModal({ onClose, onAdded }) {
  const [tab, setTab] = useState('KO')

  // 입력 단계
  const [code, setCode] = useState('')
  const [looking, setLooking] = useState(false)
  const [lookupErr, setLookupErr] = useState('')

  // 조회 후 편집 필드
  const [looked, setLooked] = useState(false)
  const [name, setName] = useState('')
  const [rarityCode, setRarityCode] = useState('')
  const [collectionNumber, setCollectionNumber] = useState('')
  const [productId, setProductId] = useState('')
  const [productSearch, setProductSearch] = useState('')
  const [enRef, setEnRef] = useState('')
  const [jpRef, setJpRef] = useState('')

  // 세트 목록
  const [products, setProducts] = useState([])

  // 제출
  const [submitting, setSubmitting] = useState(false)
  const [submitErr, setSubmitErr] = useState('')

  // 탭 바꾸면 전부 초기화
  const switchTab = (t) => {
    setTab(t); setCode(''); setLooking(false); setLookupErr(''); setLooked(false)
    setName(''); setRarityCode(''); setCollectionNumber(''); setProductId('')
    setProductSearch(''); setEnRef(''); setJpRef(''); setSubmitErr('')
  }

  useEffect(() => {
    api.get('/admin/products', { params: { search: productSearch || undefined } })
      .then(r => setProducts(r.data?.data ?? []))
      .catch(() => setProducts([]))
  }, [productSearch])

  const handleLookup = async () => {
    if (!code.trim()) return setLookupErr('코드를 입력하세요.')
    setLooking(true); setLookupErr(''); setLooked(false)
    try {
      const r = await api.get('/admin/cards/lookup', { params: { type: tab, code: code.trim() } })
      const d = r.data?.data ?? {}
      setName(d.name ?? '')
      setRarityCode(d.rarityCode ?? '')
      setCollectionNumber(d.collectionNumber ?? '')
      setProductId(d.productId ?? '')
      // 세트 드롭다운 검색어를 세트명으로 초기화해서 pre-filter
      if (d.productName) setProductSearch(d.productName.split(' ')[0])
      if (tab === 'EN') setEnRef(code.trim())
      if (tab === 'JP') setJpRef(code.trim())
      setLooked(true)
    } catch (e) {
      setLookupErr(e.response?.data?.message ?? '조회 실패. 코드를 확인하세요.')
    } finally {
      setLooking(false)
    }
  }

  const handleSubmit = async () => {
    if (!name.trim())     return setSubmitErr('카드명을 입력하세요.')
    if (!productId)       return setSubmitErr('세트를 선택하세요.')
    if (!rarityCode)      return setSubmitErr('희귀도를 선택하세요.')

    const body = {
      type: tab,
      name: name.trim(),
      productId,
      rarityCode,
      collectionNumber: collectionNumber || null,
      enScrydexRef: (tab === 'EN' ? code.trim() : enRef) || null,
      jpScrydexRef: (tab === 'JP' ? code.trim() : jpRef) || null,
      officialCardCode: tab === 'KO' ? code.trim() : null,
    }

    setSubmitting(true); setSubmitErr('')
    try {
      await api.post('/admin/cards', body)
      onAdded(); onClose()
    } catch (e) {
      setSubmitErr(e.response?.data?.message ?? '추가 실패')
    } finally {
      setSubmitting(false)
    }
  }

  const inp = {
    width: '100%', padding: '9px 12px', borderRadius: 8, border: '1px solid #e2e8f0',
    fontSize: 13, color: '#1e293b', outline: 'none', fontFamily: 'inherit', boxSizing: 'border-box',
  }
  const lbl = { fontSize: 12, fontWeight: 600, color: '#64748b', marginBottom: 4, display: 'block' }
  const row = { marginBottom: 14 }

  const TABS = [
    { id: 'KO', flag: '🇰🇷', label: 'KO',  hint: 'BS2023014205',  desc: '포켓몬 코리아 오피셜 코드' },
    { id: 'EN', flag: '🇺🇸', label: 'EN',  hint: 'swsh8-269',     desc: 'Scrydex EN ref' },
    { id: 'JP', flag: '🇯🇵', label: 'JP',  hint: 'm3_ja-117',     desc: 'Scrydex JP ref' },
  ]
  const cur = TABS.find(t => t.id === tab)

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.45)', zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}
      onClick={e => e.target === e.currentTarget && onClose()}>
      <div style={{ background: '#fff', borderRadius: 16, width: 480, maxHeight: '90vh', overflow: 'auto', boxShadow: '0 20px 60px rgba(0,0,0,0.18)' }}>

        {/* 헤더 */}
        <div style={{ padding: '20px 24px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ fontSize: 16, fontWeight: 700, color: '#1e293b' }}>카드 추가</span>
          <button onClick={onClose} style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#94a3b8', padding: 4 }}><X size={18} /></button>
        </div>

        {/* 탭 */}
        <div style={{ display: 'flex', padding: '14px 24px 0', gap: 2, borderBottom: '1px solid #f1f5f9' }}>
          {TABS.map(t => (
            <button key={t.id} onClick={() => switchTab(t.id)} style={{
              padding: '8px 16px', border: 'none', background: 'none', cursor: 'pointer',
              fontSize: 13, fontWeight: tab === t.id ? 700 : 400,
              color: tab === t.id ? '#6366f1' : '#64748b',
              borderBottom: tab === t.id ? '2px solid #6366f1' : '2px solid transparent',
              marginBottom: -1, fontFamily: 'inherit',
            }}>{t.flag} {t.label}</button>
          ))}
        </div>

        <div style={{ padding: '20px 24px' }}>

          {/* ── STEP 1: 코드 입력 + 조회 ── */}
          <div style={{ marginBottom: 16 }}>
            <label style={lbl}>{cur.desc} *</label>
            <div style={{ display: 'flex', gap: 8 }}>
              <input
                style={{ ...inp, flex: 1 }}
                placeholder={cur.hint}
                value={code}
                onChange={e => { setCode(e.target.value); setLooked(false); setLookupErr('') }}
                onKeyDown={e => e.key === 'Enter' && handleLookup()}
              />
              <button onClick={handleLookup} disabled={looking} style={{
                padding: '9px 16px', borderRadius: 8, border: 'none', cursor: looking ? 'not-allowed' : 'pointer',
                background: looking ? '#e2e8f0' : '#6366f1', color: looking ? '#94a3b8' : '#fff',
                fontSize: 13, fontWeight: 600, fontFamily: 'inherit', whiteSpace: 'nowrap',
              }}>{looking ? '조회 중...' : '조회'}</button>
            </div>
            {lookupErr && (
              <div style={{ marginTop: 8, padding: '8px 12px', background: '#fef2f2', borderRadius: 8, color: '#dc2626', fontSize: 12 }}>
                {lookupErr}
              </div>
            )}
          </div>

          {/* ── STEP 2: 조회 결과 편집 + 추가 ── */}
          {looked && (
            <>
              <div style={{ height: 1, background: '#f1f5f9', margin: '0 0 16px' }} />

              <div style={row}>
                <label style={lbl}>카드명 (KO) *</label>
                <input style={inp} value={name} onChange={e => setName(e.target.value)}
                  placeholder="카드명을 입력하세요" />
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 14 }}>
                <div>
                  <label style={lbl}>희귀도 *</label>
                  <select style={{ ...inp, background: '#fff' }} value={rarityCode}
                    onChange={e => setRarityCode(e.target.value)}>
                    <option value="">선택</option>
                    {RARITY_OPTIONS.map(r => <option key={r} value={r}>{r}</option>)}
                  </select>
                </div>
                <div>
                  <label style={lbl}>수록번호</label>
                  <input style={inp} placeholder="117/080" value={collectionNumber}
                    onChange={e => setCollectionNumber(e.target.value)} />
                </div>
              </div>

              <div style={row}>
                <label style={lbl}>세트 *</label>
                <input style={{ ...inp, marginBottom: 6 }} placeholder="세트 검색..."
                  value={productSearch} onChange={e => setProductSearch(e.target.value)} />
                <select style={{ ...inp, background: '#fff' }} size={4} value={productId}
                  onChange={e => setProductId(e.target.value)}>
                  <option value="">-- 선택 --</option>
                  {products.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
              </div>

              {/* 크로스 ref (선택) */}
              {tab !== 'EN' && (
                <div style={row}>
                  <label style={lbl}>EN Scrydex Ref (선택)</label>
                  <input style={inp} placeholder="swsh8-269" value={enRef}
                    onChange={e => setEnRef(e.target.value)} />
                </div>
              )}
              {tab !== 'JP' && (
                <div style={row}>
                  <label style={lbl}>JP Scrydex Ref (선택)</label>
                  <input style={inp} placeholder="m3_ja-117" value={jpRef}
                    onChange={e => setJpRef(e.target.value)} />
                </div>
              )}

              {submitErr && (
                <div style={{ padding: '10px 14px', background: '#fef2f2', borderRadius: 8, color: '#dc2626', fontSize: 13, marginBottom: 14 }}>
                  {submitErr}
                </div>
              )}

              <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
                <button onClick={onClose} style={{
                  padding: '9px 18px', borderRadius: 10, border: '1px solid #e2e8f0',
                  background: '#fff', color: '#64748b', fontSize: 13, fontWeight: 600, cursor: 'pointer', fontFamily: 'inherit',
                }}>취소</button>
                <button onClick={handleSubmit} disabled={submitting} style={{
                  padding: '9px 18px', borderRadius: 10, border: 'none',
                  background: submitting ? '#a5b4fc' : 'linear-gradient(135deg, #6366f1 0%, #4f46e5 100%)',
                  color: '#fff', fontSize: 13, fontWeight: 600, cursor: submitting ? 'not-allowed' : 'pointer', fontFamily: 'inherit',
                }}>{submitting ? '추가 중...' : '카드 추가'}</button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}

export default function Cards() {
  const [cards, setCards] = useState([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(0)
  const [search, setSearch] = useState('')
  const [rarity, setRarity] = useState('전체')
  const [loading, setLoading] = useState(true)
  const [showAdd, setShowAdd] = useState(false)
  const size = 15

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
      {showAdd && <AddCardModal onClose={() => setShowAdd(false)} onAdded={load} />}

      <div style={S.header}>
        <div>
          <div style={S.h1}>카드 관리</div>
          <div style={S.sub}>총 {total.toLocaleString()}장의 카드 (KO 기준)</div>
        </div>
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
