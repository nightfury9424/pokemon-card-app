import { useEffect, useState } from 'react'
import { Search, ChevronLeft, ChevronRight, Trash2 } from 'lucide-react'
import api from '../api'

// 2026-05-29 admin Stage 0 — admin 거래글 삭제 inline action.
async function adminDeleteTrade(tradeId) {
  const reason = prompt(`거래글 ${tradeId} 삭제 사유 (audit log):`)
  if (!reason || !reason.trim()) return false
  if (!confirm(`${tradeId} soft delete + 양쪽 채팅방 SYSTEM 알림 진행할까요?`)) return false
  try {
    await api.delete(`/admin/trade-posts/${tradeId}`, { data: { reason: reason.trim() } })
    return true
  } catch (e) {
    const msg = e.response?.data?.message ?? '삭제 처리 실패'
    if (msg.includes('TRADE_NOT_FOUND')) alert('거래글을 찾을 수 없어요')
    else alert(msg)
    return false
  }
}

const S = {
  page:   { padding: '32px 36px', minHeight: '100%', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' },
  header: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 },
  h1:     { fontSize: 22, fontWeight: 700, color: '#1e293b', letterSpacing: -0.5 },
  sub:    { fontSize: 13, color: '#94a3b8', marginTop: 3 },
  card:   { background: '#fff', borderRadius: 16, border: '1px solid #e8edf4', boxShadow: '0 1px 3px rgba(0,0,0,0.04)', overflow: 'hidden' },
  th:     { padding: '12px 16px', fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.6, textAlign: 'left', background: '#f8fafc', borderBottom: '1px solid #f1f5f9' },
  td:     { padding: '13px 16px', fontSize: 13, color: '#475569', borderBottom: '1px solid #f8fafc' },
}

const TABS = ['전체', '진행중', '완료', '취소']
const TAB_STATUS = { '진행중': 'ACTIVE', '완료': 'COMPLETED', '취소': 'CANCELLED' }

const STATUS_MAP = {
  ACTIVE:    { label: '진행중', bg: '#eff6ff', color: '#2563eb', border: '#bfdbfe' },
  COMPLETED: { label: '완료',   bg: '#f0fdf4', color: '#16a34a', border: '#bbf7d0' },
  CANCELLED: { label: '취소',   bg: '#fef2f2', color: '#dc2626', border: '#fecaca' },
  PENDING:   { label: '대기중', bg: '#fff7ed', color: '#c2410c', border: '#fed7aa' },
}

function StatusBadge({ status }) {
  const s = STATUS_MAP[status] ?? STATUS_MAP.ACTIVE
  return (
    <span style={{ fontSize: 11, fontWeight: 600, padding: '3px 8px', borderRadius: 99, background: s.bg, color: s.color, border: `1px solid ${s.border}` }}>
      {s.label}
    </span>
  )
}

export default function Trades() {
  const [trades, setTrades] = useState([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(0)
  const [tab, setTab] = useState('전체')
  const [search, setSearch] = useState('')
  const [loading, setLoading] = useState(true)
  const size = 15

  useEffect(() => {
    setLoading(true)
    api.get('/admin/trades', {
      params: { page, size, status: TAB_STATUS[tab], search: search || undefined }
    })
      .then(r => {
        setTrades(r.data?.data?.content ?? [])
        setTotal(r.data?.data?.totalElements ?? 0)
      })
      .catch(() => { setTrades([]); setTotal(0) })
      .finally(() => setLoading(false))
  }, [page, tab, search])

  const totalPages = Math.ceil(total / size)

  return (
    <div style={S.page}>
      <div style={S.header}>
        <div>
          <div style={S.h1}>거래 관리</div>
          <div style={S.sub}>총 {total.toLocaleString()}건의 거래</div>
        </div>
      </div>

      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
        <div style={{ display: 'flex', gap: 6 }}>
          {TABS.map(t => (
            <button key={t} onClick={() => { setTab(t); setPage(0) }} style={{
              padding: '7px 16px', borderRadius: 99, border: '1px solid',
              fontSize: 13, cursor: 'pointer', fontFamily: 'inherit', transition: 'all 0.1s',
              background: tab === t ? '#6366f1' : '#fff',
              color: tab === t ? '#fff' : '#64748b',
              borderColor: tab === t ? '#6366f1' : '#e2e8f0',
              fontWeight: tab === t ? 600 : 400,
            }}>{t}</button>
          ))}
        </div>
        <div style={{ position: 'relative', width: 260 }}>
          <Search size={14} style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', color: '#94a3b8' }} />
          <input
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(0) }}
            placeholder="거래 제목 검색"
            style={{
              width: '100%', padding: '9px 12px 9px 34px', borderRadius: 10,
              border: '1px solid #e2e8f0', background: '#fff', fontSize: 13,
              color: '#1e293b', outline: 'none', fontFamily: 'inherit',
            }}
          />
        </div>
      </div>

      <div style={S.card}>
        {/* 2026-05-29 P-1: 9개 컬럼 + 사이드바 폭 합치면 자주 좁아져서 글자 세로 쪼개짐 ("유 형", "진 행 중").
            wrapper overflow-x:auto + table min-width 로 가로 스크롤 허용. */}
        <div style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', minWidth: 1100, borderCollapse: 'collapse', tableLayout: 'auto' }}>
          <thead>
            <tr>
              {['ID', '제목', '작성자', '유형', '희망 카드', '제안 카드', '등록일', '상태', '액션'].map(h => (
                <th key={h} style={{ ...S.th, whiteSpace: 'nowrap' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={9} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>불러오는 중...</td></tr>
            ) : trades.length === 0 ? (
              <tr><td colSpan={9} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>거래글이 없습니다</td></tr>
            ) : trades.map(t => {
              const tradeId = t.id || t.tradeId
              const isDeleted = t.status === 'DELETED' || t.status === 'CANCELLED'
              return (
              <tr key={tradeId}
                onMouseEnter={e => e.currentTarget.style.background = '#fafafa'}
                onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
              >
                <td style={{ ...S.td, color: '#94a3b8', fontSize: 12 }}>{tradeId}</td>
                <td style={{ ...S.td, fontWeight: 600, color: '#1e293b', maxWidth: 180 }}>
                  <span style={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{t.title ?? '-'}</span>
                </td>
                <td style={S.td}>{t.authorNickname ?? '-'}</td>
                <td style={{ ...S.td, whiteSpace: 'nowrap' }}>{t.tradeType === 'EXCHANGE' ? '교환' : t.tradeType === 'SELL' ? '판매' : '-'}</td>
                <td style={{ ...S.td, fontSize: 12, whiteSpace: 'nowrap' }}>{t.wantCardName ?? '-'}</td>
                <td style={{ ...S.td, fontSize: 12, whiteSpace: 'nowrap' }}>{t.offerCardName ?? '-'}</td>
                <td style={{ ...S.td, fontSize: 12, whiteSpace: 'nowrap' }}>{t.createdAt ? t.createdAt.slice(0, 10) : '-'}</td>
                <td style={{ ...S.td, whiteSpace: 'nowrap' }}><StatusBadge status={t.status} /></td>
                <td style={{ ...S.td, whiteSpace: 'nowrap' }}>
                  {isDeleted ? (
                    <span style={{ color: '#cbd5e1', fontSize: 11 }}>삭제됨</span>
                  ) : (
                    <button onClick={async () => {
                      const ok = await adminDeleteTrade(tradeId)
                      if (ok) {
                        api.get('/admin/trades', { params: { page, size, status: TAB_STATUS[tab], search: search || undefined } })
                          .then(r => { setTrades(r.data?.data?.content ?? []); setTotal(r.data?.data?.totalElements ?? 0) })
                      }
                    }} style={{
                      display: 'inline-flex', alignItems: 'center', gap: 4,
                      padding: '4px 10px', borderRadius: 6,
                      background: '#fff', border: '1px solid #dc2626',
                      color: '#dc2626', fontSize: 11, fontWeight: 600, cursor: 'pointer',
                    }}><Trash2 size={12} /> admin 삭제</button>
                  )}
                </td>
              </tr>
              )
            })}
          </tbody>
        </table>
        </div>

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
