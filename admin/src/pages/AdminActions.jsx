// 2026-06-07 운영 관측성 Phase 1 — 운영(감사) 로그 뷰어.
//   admin_actions 는 SUSPEND/WARN/DELETE_TRADE 등 모든 운영 mutation 을 기록하지만
//   조회 화면이 없었음. "누가 언제 무엇을 어떻게 처리했는지"를 운영자가 보게 한다.
//   backend: GET /api/admin/admin-actions?actionType=&targetType=&page=&size=

import { useEffect, useState } from 'react'
import { ScrollText, ChevronLeft, ChevronRight, RefreshCw } from 'lucide-react'
import api from '../api'

const S = {
  page:   { padding: '32px 36px', minHeight: '100%', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' },
  header: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 },
  h1:     { fontSize: 22, fontWeight: 700, color: '#1e293b', letterSpacing: -0.5 },
  sub:    { fontSize: 13, color: '#94a3b8', marginTop: 3 },
  card:   { background: '#fff', borderRadius: 16, border: '1px solid #e8edf4', boxShadow: '0 1px 3px rgba(0,0,0,0.04)', overflow: 'hidden' },
  th:     { padding: '12px 16px', fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.6, textAlign: 'left', background: '#f8fafc', borderBottom: '1px solid #f1f5f9', whiteSpace: 'nowrap' },
  td:     { padding: '13px 16px', fontSize: 13, color: '#475569', borderBottom: '1px solid #f8fafc', verticalAlign: 'top' },
  select: { padding: '8px 12px', borderRadius: 10, border: '1px solid #e2e8f0', background: '#fff', fontSize: 13, color: '#1e293b', outline: 'none', fontFamily: 'inherit', cursor: 'pointer' },
  refresh:{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, fontWeight: 600, padding: '8px 14px', borderRadius: 8, border: '1px solid #e2e8f0', background: '#fff', color: '#475569', cursor: 'pointer' },
}

// 액션 타입 한글 라벨 + 색 (모르는 타입은 raw 표시)
const ACTION_META = {
  SUSPEND:             { label: '정지',       color: '#dc2626', bg: '#fef2f2' },
  UNSUSPEND:           { label: '정지 해제',   color: '#16a34a', bg: '#f0fdf4' },
  WARN:                { label: '경고',       color: '#d97706', bg: '#fffbeb' },
  AUTO_SUSPEND:        { label: '자동 정지',   color: '#b91c1c', bg: '#fef2f2' },
  DELETE_TRADE:        { label: '거래글 삭제', color: '#dc2626', bg: '#fef2f2' },
  DELETE_CHAT_MESSAGE: { label: '채팅 삭제',   color: '#dc2626', bg: '#fef2f2' },
  REVIEW_REPORT:       { label: '신고 처리',   color: '#2563eb', bg: '#eff6ff' },
  DISMISS_REPORT:      { label: '신고 기각',   color: '#64748b', bg: '#f8fafc' },
  RESOLVE_ANOMALY:     { label: '이상가 처리', color: '#7c3aed', bg: '#faf5ff' },
}

const TARGET_LABEL = {
  USER: '유저', TRADE: '거래글', REPORT: '신고', CHAT_MESSAGE: '채팅', PRICE_ANOMALY: '가격이상',
}

const ACTION_OPTIONS = ['', 'SUSPEND', 'UNSUSPEND', 'WARN', 'AUTO_SUSPEND', 'DELETE_TRADE', 'REVIEW_REPORT', 'DISMISS_REPORT']
const TARGET_OPTIONS = ['', 'USER', 'TRADE', 'REPORT', 'CHAT_MESSAGE']

function ActionBadge({ type }) {
  const m = ACTION_META[type] ?? { label: type ?? '-', color: '#64748b', bg: '#f8fafc' }
  return (
    <span style={{ fontSize: 11, fontWeight: 700, padding: '3px 8px', borderRadius: 99, background: m.bg, color: m.color, whiteSpace: 'nowrap' }}>
      {m.label}
    </span>
  )
}

function fmt(ts) {
  if (!ts) return '-'
  const d = new Date(ts)
  if (Number.isNaN(d.getTime())) return String(ts).split('.')[0].replace('T', ' ')
  const p = n => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`
}

export default function AdminActions() {
  const [rows, setRows] = useState([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(0)
  const [actionType, setActionType] = useState('')
  const [targetType, setTargetType] = useState('')
  const [loading, setLoading] = useState(true)
  const size = 30

  function load() {
    setLoading(true)
    api.get('/admin/admin-actions', {
      params: { actionType: actionType || undefined, targetType: targetType || undefined, page, size },
    })
      .then(r => {
        setRows(r.data?.data?.content ?? [])
        setTotal(r.data?.data?.totalElements ?? 0)
      })
      .catch(() => { setRows([]); setTotal(0) })
      .finally(() => setLoading(false))
  }

  useEffect(() => { load() }, [page, actionType, targetType])

  const totalPages = Math.ceil(total / size)

  return (
    <div style={S.page}>
      <div style={S.header}>
        <div>
          <h1 style={S.h1}><ScrollText size={20} style={{ verticalAlign: -3, marginRight: 8 }} />운영 로그</h1>
          <div style={S.sub}>관리자 조치 감사 기록 · 총 {total.toLocaleString()}건</div>
        </div>
        <button style={S.refresh} onClick={load} disabled={loading}>
          <RefreshCw size={14} style={{ animation: loading ? 'spin 1s linear infinite' : 'none' }} /> 새로고침
        </button>
      </div>

      {/* 필터 */}
      <div style={{ display: 'flex', gap: 10, marginBottom: 16 }}>
        <select style={S.select} value={actionType} onChange={e => { setActionType(e.target.value); setPage(0) }}>
          {ACTION_OPTIONS.map(o => (
            <option key={o} value={o}>{o === '' ? '전체 액션' : (ACTION_META[o]?.label ?? o)}</option>
          ))}
        </select>
        <select style={S.select} value={targetType} onChange={e => { setTargetType(e.target.value); setPage(0) }}>
          {TARGET_OPTIONS.map(o => (
            <option key={o} value={o}>{o === '' ? '전체 대상' : (TARGET_LABEL[o] ?? o)}</option>
          ))}
        </select>
      </div>

      <div style={S.card}>
        <div style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', minWidth: 900, borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              {['시각', '관리자', '액션', '대상', '변경(전→후)', '메모'].map(h => (
                <th key={h} style={S.th}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={6} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>불러오는 중...</td></tr>
            ) : rows.length === 0 ? (
              <tr><td colSpan={6} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>운영 기록이 없습니다</td></tr>
            ) : rows.map(r => (
              <tr key={r.actionId}
                onMouseEnter={e => e.currentTarget.style.background = '#fafafa'}
                onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
              >
                <td style={{ ...S.td, whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums', fontSize: 12 }}>{fmt(r.createdAt)}</td>
                <td style={{ ...S.td, whiteSpace: 'nowrap' }}>
                  {r.adminNickname || <span style={{ fontFamily: 'monospace', fontSize: 11, color: '#94a3b8' }}>{r.adminUserId}</span>}
                </td>
                <td style={S.td}><ActionBadge type={r.actionType} /></td>
                <td style={{ ...S.td, whiteSpace: 'nowrap' }}>
                  <span style={{ color: '#64748b' }}>{TARGET_LABEL[r.targetType] ?? r.targetType}</span>
                  <span style={{ fontFamily: 'monospace', fontSize: 11, color: '#cbd5e1', marginLeft: 6 }}>{r.targetId}</span>
                </td>
                <td style={{ ...S.td, fontSize: 12, whiteSpace: 'nowrap' }}>
                  {(r.previousState || r.newState)
                    ? <span><span style={{ color: '#94a3b8' }}>{r.previousState ?? '-'}</span> → <span style={{ color: '#1e293b', fontWeight: 600 }}>{r.newState ?? '-'}</span></span>
                    : <span style={{ color: '#cbd5e1' }}>-</span>}
                </td>
                <td style={{ ...S.td, maxWidth: 280 }}>
                  <div style={{ display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden', lineHeight: 1.5 }}>{r.memo || '-'}</div>
                </td>
              </tr>
            ))}
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
