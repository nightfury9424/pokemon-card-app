import { useEffect, useState } from 'react'
import { Search, ChevronLeft, ChevronRight, Ban, Undo2 } from 'lucide-react'
import api from '../api'

// 2026-05-29 admin Stage 0 — 정지/복구 inline action.
async function suspendUser(userId) {
  const reason = prompt('정지 사유 (audit log 기록):')
  if (!reason || !reason.trim()) return false
  if (!confirm(`정지 처리할까요? 사유: ${reason}`)) return false
  try {
    await api.post(`/admin/users/${userId}/suspend`, { reason: reason.trim() })
    return true
  } catch (e) {
    const msg = e.response?.data?.message ?? '정지 처리 실패'
    if (msg.includes('ADMIN_USER_NOT_SUSPENDABLE')) alert('관리자 계정은 정지할 수 없어요')
    else if (msg.includes('USER_ALREADY_DELETED')) alert('이미 탈퇴한 사용자에요')
    else alert(msg)
    return false
  }
}

async function unsuspendUser(userId) {
  if (!confirm('정지 해제할까요?')) return false
  try {
    await api.post(`/admin/users/${userId}/unsuspend`, {})
    return true
  } catch (e) {
    alert(e.response?.data?.message ?? '정지 해제 실패')
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

function Badge({ status }) {
  const map = {
    ACTIVE:   { label: '활성', bg: '#f0fdf4', color: '#16a34a', border: '#bbf7d0' },
    BANNED:   { label: '정지', bg: '#fef2f2', color: '#dc2626', border: '#fecaca' },
    INACTIVE: { label: '비활성', bg: '#f8fafc', color: '#64748b', border: '#e2e8f0' },
  }
  const s = map[status] ?? map.INACTIVE
  return (
    <span style={{
      fontSize: 11, fontWeight: 600, padding: '3px 8px', borderRadius: 99,
      background: s.bg, color: s.color, border: `1px solid ${s.border}`,
    }}>{s.label}</span>
  )
}

export default function Users() {
  const [users, setUsers] = useState([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(0)
  const [search, setSearch] = useState('')
  const [loading, setLoading] = useState(true)
  const size = 15

  useEffect(() => {
    setLoading(true)
    api.get('/admin/users', { params: { page, size, search: search || undefined } })
      .then(r => {
        setUsers(r.data?.data?.content ?? [])
        setTotal(r.data?.data?.totalElements ?? 0)
      })
      .catch(() => { setUsers([]); setTotal(0) })
      .finally(() => setLoading(false))
  }, [page, search])

  const totalPages = Math.ceil(total / size)

  return (
    <div style={S.page}>
      <div style={S.header}>
        <div>
          <div style={S.h1}>유저 관리</div>
          <div style={S.sub}>총 {total.toLocaleString()}명의 유저</div>
        </div>
      </div>

      {/* 검색 */}
      <div style={{ position: 'relative', marginBottom: 16, width: 320 }}>
        <Search size={14} style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', color: '#94a3b8' }} />
        <input
          value={search}
          onChange={e => { setSearch(e.target.value); setPage(0) }}
          placeholder="닉네임 또는 이메일 검색"
          style={{
            width: '100%', padding: '9px 12px 9px 34px', borderRadius: 10,
            border: '1px solid #e2e8f0', background: '#fff', fontSize: 13,
            color: '#1e293b', outline: 'none', fontFamily: 'inherit',
          }}
        />
      </div>

      <div style={S.card}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              {['ID', '닉네임', '이메일', '가입일', '스캔', '거래', '상태', '액션'].map(h => (
                <th key={h} style={S.th}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={8} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>불러오는 중...</td></tr>
            ) : users.length === 0 ? (
              <tr><td colSpan={8} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>유저가 없습니다</td></tr>
            ) : users.map(u => {
              // 백엔드 응답: suspended (boolean) / status (legacy). suspended true 면 정지 상태.
              const isSuspended = u.suspended === true || u.status === 'BANNED'
              const isDeleted = u.deleted === true || u.deletedAt
              return (
              <tr key={u.id || u.userId} style={{ transition: 'background 0.1s' }}
                onMouseEnter={e => e.currentTarget.style.background = '#fafafa'}
                onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
              >
                <td style={{ ...S.td, color: '#94a3b8', fontSize: 12 }}>{u.id || u.userId}</td>
                <td style={{ ...S.td, fontWeight: 600, color: '#1e293b' }}>{u.nickname ?? '-'}</td>
                <td style={S.td}>{u.email ?? '-'}</td>
                <td style={{ ...S.td, fontSize: 12 }}>{u.createdAt ? u.createdAt.slice(0, 10) : '-'}</td>
                <td style={S.td}>{(u.scanCount ?? 0).toLocaleString()}</td>
                <td style={S.td}>{(u.tradeCount ?? 0).toLocaleString()}</td>
                <td style={S.td}><Badge status={isDeleted ? 'INACTIVE' : (isSuspended ? 'BANNED' : 'ACTIVE')} /></td>
                <td style={S.td}>
                  {isDeleted ? (
                    <span style={{ color: '#cbd5e1', fontSize: 11 }}>탈퇴</span>
                  ) : isSuspended ? (
                    <button onClick={async () => {
                      const ok = await unsuspendUser(u.id || u.userId)
                      if (ok) { setPage(p => p); /* trigger re-fetch */ setUsers(prev => prev.filter(x => (x.id || x.userId) !== (u.id || u.userId))); api.get('/admin/users', { params: { page, size, search: search || undefined } }).then(r => { setUsers(r.data?.data?.content ?? []); setTotal(r.data?.data?.totalElements ?? 0) }) }
                    }} style={{
                      display: 'inline-flex', alignItems: 'center', gap: 4,
                      padding: '4px 10px', borderRadius: 6,
                      background: '#fff', border: '1px solid #16a34a',
                      color: '#16a34a', fontSize: 11, fontWeight: 600, cursor: 'pointer',
                    }}><Undo2 size={12} /> 정지 해제</button>
                  ) : (
                    <button onClick={async () => {
                      const ok = await suspendUser(u.id || u.userId)
                      if (ok) api.get('/admin/users', { params: { page, size, search: search || undefined } }).then(r => { setUsers(r.data?.data?.content ?? []); setTotal(r.data?.data?.totalElements ?? 0) })
                    }} style={{
                      display: 'inline-flex', alignItems: 'center', gap: 4,
                      padding: '4px 10px', borderRadius: 6,
                      background: '#fff', border: '1px solid #dc2626',
                      color: '#dc2626', fontSize: 11, fontWeight: 600, cursor: 'pointer',
                    }}><Ban size={12} /> 정지</button>
                  )}
                </td>
              </tr>
              )
            })}
          </tbody>
        </table>

        {/* 페이지네이션 */}
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
