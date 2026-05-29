// 2026-05-29 admin Stage 0 — 신고 처리 페이지.
//   backend endpoints: GET /api/admin/reports + PATCH /api/admin/reports/{id}/status
//   기존 Users.jsx 스타일 일관 — 흰 카드 + 보라 헤더 + 검색/필터.

import { useEffect, useState } from 'react'
import { Flag, AlertCircle, Check, X, RefreshCw } from 'lucide-react'
import api from '../api'

const S = {
  page:   { padding: '32px 36px', minHeight: '100%', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' },
  header: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 },
  h1:     { fontSize: 22, fontWeight: 700, color: '#1e293b', letterSpacing: -0.5 },
  sub:    { fontSize: 13, color: '#94a3b8', marginTop: 3 },
  card:   { background: '#fff', borderRadius: 16, border: '1px solid #e8edf4', boxShadow: '0 1px 3px rgba(0,0,0,0.04)', overflow: 'hidden' },
  th:     { padding: '12px 16px', fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.6, textAlign: 'left', background: '#f8fafc', borderBottom: '1px solid #f1f5f9' },
  td:     { padding: '13px 16px', fontSize: 13, color: '#475569', borderBottom: '1px solid #f8fafc', verticalAlign: 'top' },
  btnSm:  { fontSize: 11, fontWeight: 600, padding: '5px 10px', borderRadius: 6, border: 'none', cursor: 'pointer' },
}

const STATUS_MAP = {
  PENDING:   { label: '대기', bg: '#fff7ed', color: '#c2410c', border: '#fed7aa' },
  REVIEWED:  { label: '검토', bg: '#eff6ff', color: '#2563eb', border: '#bfdbfe' },
  RESOLVED:  { label: '해결', bg: '#f0fdf4', color: '#16a34a', border: '#bbf7d0' },
  DISMISSED: { label: '기각', bg: '#f8fafc', color: '#64748b', border: '#e2e8f0' },
}

function StatusBadge({ status }) {
  const s = STATUS_MAP[status] ?? STATUS_MAP.PENDING
  return (
    <span style={{
      fontSize: 11, fontWeight: 600, padding: '3px 8px', borderRadius: 99,
      background: s.bg, color: s.color, border: `1px solid ${s.border}`,
    }}>{s.label}</span>
  )
}

export default function Reports() {
  const [rows, setRows] = useState([])
  const [pendingCount, setPendingCount] = useState(0)
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(0)
  const [statusFilter, setStatusFilter] = useState('PENDING')
  const [targetFilter, setTargetFilter] = useState('ALL')
  const [loading, setLoading] = useState(true)
  const [modalRow, setModalRow] = useState(null)
  const size = 20

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, statusFilter, targetFilter])

  async function load() {
    setLoading(true)
    try {
      const params = { page, size }
      if (statusFilter !== 'ALL') params.status = statusFilter
      if (targetFilter !== 'ALL') params.targetType = targetFilter
      const r = await api.get('/admin/reports', { params })
      setRows(r.data?.data?.content ?? [])
      setTotal(r.data?.data?.totalElements ?? 0)
      setPendingCount(r.data?.data?.pendingCount ?? 0)
    } catch {
      setRows([])
      setTotal(0)
    } finally {
      setLoading(false)
    }
  }

  const totalPages = Math.ceil(total / size)

  return (
    <div style={S.page}>
      <div style={S.header}>
        <div>
          <div style={S.h1}>신고 처리</div>
          <div style={S.sub}>총 {total.toLocaleString()}건 · 대기 <strong style={{ color: '#c2410c' }}>{pendingCount.toLocaleString()}건</strong></div>
        </div>
        <button
          onClick={load}
          disabled={loading}
          style={{
            display: 'flex', alignItems: 'center', gap: 6,
            padding: '8px 14px', borderRadius: 10,
            background: '#fff', border: '1px solid #e2e8f0', cursor: 'pointer',
            color: '#475569', fontSize: 12, fontWeight: 600,
          }}>
          <RefreshCw size={13} /> 새로고침
        </button>
      </div>

      {/* 필터 row */}
      <div style={{ display: 'flex', gap: 8, marginBottom: 16, flexWrap: 'wrap' }}>
        {['ALL', 'PENDING', 'REVIEWED', 'RESOLVED', 'DISMISSED'].map(s => {
          const sel = statusFilter === s
          return (
            <button
              key={s}
              onClick={() => { setStatusFilter(s); setPage(0) }}
              style={{
                padding: '6px 12px', borderRadius: 99,
                background: sel ? '#4f46e5' : '#fff',
                border: sel ? '1px solid #4f46e5' : '1px solid #e2e8f0',
                color: sel ? '#fff' : '#475569',
                fontSize: 12, fontWeight: 600, cursor: 'pointer',
              }}>
              {s === 'ALL' ? '전체' : (STATUS_MAP[s]?.label ?? s)}
            </button>
          )
        })}
        <div style={{ width: 1, background: '#e2e8f0', margin: '0 4px' }} />
        {['ALL', 'TRADE', 'USER', 'BUY_ORDER', 'CHAT'].map(t => {
          const sel = targetFilter === t
          return (
            <button
              key={t}
              onClick={() => { setTargetFilter(t); setPage(0) }}
              style={{
                padding: '6px 12px', borderRadius: 99,
                background: sel ? '#0ea5e9' : '#fff',
                border: sel ? '1px solid #0ea5e9' : '1px solid #e2e8f0',
                color: sel ? '#fff' : '#475569',
                fontSize: 12, fontWeight: 600, cursor: 'pointer',
              }}>
              {t === 'ALL' ? '대상 전체' : t}
            </button>
          )
        })}
      </div>

      <div style={S.card}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              {['상태', '대상', '사유', '신고자', '내용', '처리', ''].map(h => (
                <th key={h} style={S.th}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={7} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>로딩 중...</td></tr>
            ) : rows.length === 0 ? (
              <tr><td colSpan={7} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>신고 없음</td></tr>
            ) : rows.map(r => (
              <tr key={r.reportId}>
                <td style={S.td}><StatusBadge status={r.status} /></td>
                <td style={S.td}>
                  <div style={{ fontWeight: 600, color: '#1e293b' }}>{r.targetType}</div>
                  <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 2 }}>{r.targetSummary || r.targetId}</div>
                </td>
                <td style={S.td}>{r.reason}</td>
                <td style={S.td}>{r.reporterNickname || r.reporterId}</td>
                <td style={{ ...S.td, maxWidth: 280 }}>
                  <div style={{ fontSize: 12, color: '#475569', lineHeight: 1.5, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>
                    {r.detail || '-'}
                  </div>
                </td>
                <td style={S.td}>
                  {r.handledAt ? (
                    <div style={{ fontSize: 11, color: '#64748b' }}>
                      {new Date(r.handledAt).toLocaleString('ko-KR', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })}<br />
                      <span style={{ color: '#94a3b8' }}>{r.resolutionAction}</span>
                    </div>
                  ) : (
                    <span style={{ color: '#cbd5e1', fontSize: 11 }}>미처리</span>
                  )}
                </td>
                <td style={S.td}>
                  <button
                    onClick={() => setModalRow(r)}
                    style={{
                      ...S.btnSm,
                      background: r.status === 'PENDING' ? '#4f46e5' : '#fff',
                      color: r.status === 'PENDING' ? '#fff' : '#475569',
                      border: r.status === 'PENDING' ? 'none' : '1px solid #e2e8f0',
                    }}>
                    {r.status === 'PENDING' ? '처리' : '상세'}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {/* 페이지네이션 */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 16px', borderTop: '1px solid #f1f5f9' }}>
          <div style={{ fontSize: 12, color: '#94a3b8' }}>{page + 1} / {Math.max(totalPages, 1)} 페이지</div>
          <div style={{ display: 'flex', gap: 6 }}>
            <button onClick={() => setPage(p => Math.max(0, p - 1))} disabled={page === 0}
              style={{ ...S.btnSm, background: '#fff', border: '1px solid #e2e8f0', color: '#475569', padding: '6px 10px' }}>이전</button>
            <button onClick={() => setPage(p => p + 1)} disabled={page + 1 >= totalPages}
              style={{ ...S.btnSm, background: '#fff', border: '1px solid #e2e8f0', color: '#475569', padding: '6px 10px' }}>다음</button>
          </div>
        </div>
      </div>

      {modalRow && (
        <HandleModal
          row={modalRow}
          onClose={() => setModalRow(null)}
          onDone={() => { setModalRow(null); load() }}
        />
      )}
    </div>
  )
}

function HandleModal({ row, onClose, onDone }) {
  const [status, setStatus] = useState(row.status === 'PENDING' ? 'REVIEWED' : row.status)
  const [action, setAction] = useState(row.resolutionAction ?? 'NONE')
  const [memo, setMemo] = useState(row.adminMemo ?? '')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')

  const isDestructive = action === 'SUSPEND_USER' || action === 'DELETE_TRADE'

  async function submit() {
    if (isDestructive) {
      if (!confirm(`${action} 처리할까요? 한 번 처리하면 되돌릴 수 없어요.`)) return
    }
    setSubmitting(true)
    setError('')
    try {
      await api.patch(`/admin/reports/${row.reportId}/status`, {
        status,
        adminMemo: memo.trim() || null,
        resolutionAction: action,
      })
      onDone()
    } catch (e) {
      setError(e.response?.data?.message ?? '처리 실패')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div style={{
      position: 'fixed', inset: 0,
      background: 'rgba(15, 23, 42, 0.5)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      zIndex: 100,
    }} onClick={onClose}>
      <div onClick={e => e.stopPropagation()} style={{
        width: 520, background: '#fff', borderRadius: 16,
        padding: '28px', boxShadow: '0 20px 50px rgba(0,0,0,0.2)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
          <h2 style={{ fontSize: 18, fontWeight: 700, color: '#1e293b' }}>신고 처리</h2>
          <button onClick={onClose} style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#94a3b8' }}>
            <X size={20} />
          </button>
        </div>
        <div style={{ fontSize: 12, color: '#94a3b8', marginBottom: 20 }}>
          {row.targetType} · {row.reason} · 신고자: {row.reporterNickname || row.reporterId}
        </div>

        {row.detail && (
          <div style={{
            background: '#f8fafc', borderRadius: 10, padding: '12px 14px',
            marginBottom: 20, fontSize: 13, color: '#475569', lineHeight: 1.6, maxHeight: 120, overflow: 'auto',
          }}>{row.detail}</div>
        )}

        <label style={{ fontSize: 12, fontWeight: 700, color: '#64748b', display: 'block', marginBottom: 6 }}>처리 상태</label>
        <div style={{ display: 'flex', gap: 8, marginBottom: 20 }}>
          {['REVIEWED', 'RESOLVED', 'DISMISSED'].map(s => {
            const sel = status === s
            return (
              <button key={s} onClick={() => setStatus(s)} style={{
                flex: 1, padding: '10px', borderRadius: 8,
                background: sel ? '#4f46e5' : '#fff',
                border: sel ? '1px solid #4f46e5' : '1px solid #e2e8f0',
                color: sel ? '#fff' : '#475569',
                fontSize: 13, fontWeight: 600, cursor: 'pointer',
              }}>{STATUS_MAP[s].label}</button>
            )
          })}
        </div>

        <label style={{ fontSize: 12, fontWeight: 700, color: '#64748b', display: 'block', marginBottom: 6 }}>처리 액션 (선택)</label>
        <div style={{ display: 'flex', gap: 6, marginBottom: 20, flexWrap: 'wrap' }}>
          {['NONE', 'SUSPEND_USER', 'DELETE_TRADE', 'DISMISS'].map(a => {
            const sel = action === a
            const dest = a === 'SUSPEND_USER' || a === 'DELETE_TRADE'
            return (
              <button key={a} onClick={() => setAction(a)} style={{
                padding: '6px 12px', borderRadius: 99,
                background: sel ? (dest ? '#dc2626' : '#0ea5e9') : '#fff',
                border: sel ? `1px solid ${dest ? '#dc2626' : '#0ea5e9'}` : '1px solid #e2e8f0',
                color: sel ? '#fff' : '#475569',
                fontSize: 11, fontWeight: 600, cursor: 'pointer',
              }}>{a}</button>
            )
          })}
        </div>

        <label style={{ fontSize: 12, fontWeight: 700, color: '#64748b', display: 'block', marginBottom: 6 }}>처리 메모 (선택)</label>
        <textarea
          value={memo}
          onChange={e => setMemo(e.target.value)}
          placeholder="처리 근거 / 메모"
          rows={3}
          style={{
            width: '100%', padding: '10px 12px', borderRadius: 10,
            border: '1px solid #e2e8f0', background: '#f8fafc',
            fontSize: 13, color: '#1e293b', outline: 'none', resize: 'vertical', fontFamily: 'inherit',
            marginBottom: 20,
          }} />

        {error && (
          <div style={{
            padding: '10px 14px', borderRadius: 8,
            background: '#fef2f2', border: '1px solid #fecaca',
            color: '#dc2626', fontSize: 12, marginBottom: 16,
          }}>{error}</div>
        )}

        <div style={{ display: 'flex', gap: 8 }}>
          <button onClick={onClose} style={{
            flex: 1, padding: '11px', borderRadius: 10,
            background: '#fff', border: '1px solid #e2e8f0',
            color: '#475569', fontSize: 13, fontWeight: 600, cursor: 'pointer',
          }}>취소</button>
          <button onClick={submit} disabled={submitting} style={{
            flex: 2, padding: '11px', borderRadius: 10,
            background: submitting ? '#a5b4fc' : (isDestructive ? '#dc2626' : '#4f46e5'),
            color: '#fff', fontSize: 13, fontWeight: 600,
            border: 'none', cursor: submitting ? 'not-allowed' : 'pointer',
          }}>
            {submitting ? '처리 중...' : (isDestructive ? `${action} + ${STATUS_MAP[status].label}` : `${STATUS_MAP[status].label} 처리`)}
          </button>
        </div>
      </div>
    </div>
  )
}
