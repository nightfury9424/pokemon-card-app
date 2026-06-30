// 2026-05-29 admin Stage 0 — 신고 처리 페이지.
//   backend endpoints: GET /api/admin/reports + PATCH /api/admin/reports/{id}/status
//   기존 Users.jsx 스타일 일관 — 흰 카드 + 보라 헤더 + 검색/필터.

import { useEffect, useState } from 'react'
import { X, RefreshCw } from 'lucide-react'
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

// resolutionAction enum → 한글 라벨 (테이블/이력 표시용).
const ACTION_LABEL = {
  WARN_USER:    '경고 발급',
  SUSPEND_USER: '계정 정지',
  DELETE_TRADE: '거래글 삭제',
  HIDE_BOARD_POST:      '게시글 숨김',
  DELETE_BOARD_POST:    '게시글 삭제',
  DELETE_BOARD_COMMENT: '댓글 삭제',
  DISMISS:      '기각',
  NONE:         '조치 없음',
}

// ★단일 축 "조치" — 선택 하나로 집행(resolutionAction) + 신고 상태(status)를 동시에 결정.
//   기존엔 처리 상태/처리 액션 두 축을 따로 골라 모순 조합(기각인데 정지 등)이 가능했음.
const DECISIONS = [
  // 게시판 콘텐츠 조치 — 대상 타입별 노출(boardPostOnly/boardCommentOnly). 단일 축 유지(한 번에 하나).
  { key: 'HIDE_BOARD_POST',      label: '게시글 숨김', desc: '신고된 게시글을 숨겨요. 작성자 제재 없이 노출만 차단해요.', status: 'RESOLVED', tone: 'warn',   boardPostOnly: true },
  { key: 'DELETE_BOARD_POST',    label: '게시글 삭제', desc: '신고된 게시글을 삭제해요.',                              status: 'RESOLVED', tone: 'danger', boardPostOnly: true },
  { key: 'DELETE_BOARD_COMMENT', label: '댓글 삭제',   desc: '신고된 댓글을 삭제해요.',                                status: 'RESOLVED', tone: 'danger', boardCommentOnly: true },
  { key: 'WARN_USER',    label: '경고 발급',     desc: '대상 유저에게 경고를 발급해요. 누적 3회 시 자동 정지.', status: 'RESOLVED',  tone: 'warn',    needsUser: true },
  { key: 'SUSPEND_USER', label: '계정 정지',     desc: '대상 유저를 즉시 정지해 앱 이용을 차단해요.',          status: 'RESOLVED',  tone: 'danger',  needsUser: true },
  { key: 'DELETE_TRADE', label: '거래글 삭제',   desc: '신고된 거래글을 삭제해요.',                            status: 'RESOLVED',  tone: 'danger',  tradeOnly: true },
  { key: 'DISMISS',      label: '기각 (무혐의)', desc: '문제 없음으로 판단하고 조치 없이 종료해요.',           status: 'DISMISSED', tone: 'neutral' },
  { key: 'NONE',         label: '보류 (검토중)', desc: '판단을 보류하고 나중에 다시 처리해요.',                status: 'REVIEWED',  tone: 'muted' },
]

const TONE = {
  warn:    { sel: '#d97706', bg: '#fffbeb', border: '#fde68a' },
  danger:  { sel: '#dc2626', bg: '#fef2f2', border: '#fecaca' },
  neutral: { sel: '#475569', bg: '#f8fafc', border: '#e2e8f0' },
  muted:   { sel: '#64748b', bg: '#f8fafc', border: '#e2e8f0' },
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

// ── SLA — App Review 1.2 자체 약속 "24h 내 조치". createdAt 기준 마감/잔여/초과 계산. ──
const SLA_HOURS = 24
function slaInfo(row) {
  const open = row.status === 'PENDING' || row.status === 'REVIEWED'
  const created = row.createdAt ? new Date(row.createdAt).getTime() : null
  if (created == null) return { open, unknown: true }
  const remainingMs = created + SLA_HOURS * 3600000 - Date.now()
  return {
    open,
    remainingMs,
    breached: open && remainingMs < 0,
    soon: open && remainingMs >= 0 && remainingMs < 4 * 3600000,
  }
}
function fmtDur(ms) {
  const abs = Math.abs(ms)
  const h = Math.floor(abs / 3600000)
  const m = Math.floor((abs % 3600000) / 60000)
  return h > 0 ? `${h}시간 ${m}분` : `${m}분`
}
function SlaBadge({ row }) {
  const s = slaInfo(row)
  if (!s.open) return <span style={{ fontSize: 11, color: '#cbd5e1' }}>—</span>
  if (s.unknown) return <span style={{ fontSize: 11, color: '#94a3b8' }}>-</span>
  const tone = s.breached
    ? { bg: '#fef2f2', color: '#dc2626', border: '#fecaca' }
    : s.soon
    ? { bg: '#fff7ed', color: '#c2410c', border: '#fed7aa' }
    : { bg: '#f0fdf4', color: '#16a34a', border: '#bbf7d0' }
  return (
    <span style={{
      fontSize: 11, fontWeight: 700, padding: '3px 8px', borderRadius: 99,
      background: tone.bg, color: tone.color, border: `1px solid ${tone.border}`, whiteSpace: 'nowrap',
    }}>
      {s.breached ? `초과 ${fmtDur(s.remainingMs)}` : `${fmtDur(s.remainingMs)} 남음`}
    </span>
  )
}

function StatCard({ label, value, color }) {
  return (
    <div style={{ flex: 1, background: '#fff', borderRadius: 12, border: '1px solid #e8edf4', padding: '14px 16px' }}>
      <div style={{ fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.5 }}>{label}</div>
      <div style={{ fontSize: 24, fontWeight: 800, color: color ?? '#1e293b', marginTop: 4, letterSpacing: -0.5 }}>{value}</div>
    </div>
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
  const [chatRoomId, setChatRoomId] = useState(null)
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

  // 워크벤치: open(미처리) 먼저 + 오래된(마감 임박/초과)순 정렬 — 급한 게 위로.
  const displayRows = [...rows].sort((a, b) => {
    const ao = a.status === 'PENDING' || a.status === 'REVIEWED'
    const bo = b.status === 'PENDING' || b.status === 'REVIEWED'
    if (ao !== bo) return ao ? -1 : 1
    return new Date(a.createdAt || 0) - new Date(b.createdAt || 0)
  })
  // SLA 지표 — 현재 로드된 행 기준 (초기 운영 규모에선 충분, 추후 백엔드 집계로 정확화).
  const openRows = displayRows.filter(r => r.status === 'PENDING' || r.status === 'REVIEWED')
  const breachedN = openRows.filter(r => slaInfo(r).breached).length
  const soonN = openRows.filter(r => slaInfo(r).soon).length

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

      {/* SLA 지표바 — App Review 1.2 자체 약속 24h 추적 */}
      <div style={{ display: 'flex', gap: 12, marginBottom: 16 }}>
        <StatCard label="대기 (전체)" value={pendingCount.toLocaleString()} color="#c2410c" />
        <StatCard label="24h 초과 ⚠" value={breachedN} color={breachedN > 0 ? '#dc2626' : '#16a34a'} />
        <StatCard label="4h 내 마감" value={soonN} color={soonN > 0 ? '#c2410c' : '#16a34a'} />
      </div>
      {(breachedN > 0 || soonN > 0) && (
        <div style={{ fontSize: 11, color: '#94a3b8', marginTop: -8, marginBottom: 12 }}>
          ※ 초과·임박 수치는 현재 페이지 기준 (전체 집계는 백엔드 연동 예정)
        </div>
      )}

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
        {['ALL', 'TRADE', 'USER', 'BUY_ORDER', 'CHAT', 'BOARD_POST', 'BOARD_COMMENT'].map(t => {
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
              {['상태', 'SLA', '대상', '사유', '신고자', '내용', '처리', ''].map(h => (
                <th key={h} style={S.th}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={8} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>로딩 중...</td></tr>
            ) : rows.length === 0 ? (
              <tr><td colSpan={8} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>신고 없음</td></tr>
            ) : displayRows.map(r => (
              <tr key={r.reportId}>
                <td style={S.td}><StatusBadge status={r.status} /></td>
                <td style={S.td}><SlaBadge row={r} /></td>
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
                      <span style={{ color: '#94a3b8' }}>{ACTION_LABEL[r.resolutionAction] ?? r.resolutionAction ?? ''}</span>
                    </div>
                  ) : (
                    <span style={{ color: '#cbd5e1', fontSize: 11 }}>미처리</span>
                  )}
                </td>
                <td style={S.td}>
                  <div style={{ display: 'flex', gap: 6 }}>
                    {r.targetType === 'CHAT' && (
                      <button
                        onClick={() => setChatRoomId(r.targetId)}
                        style={{ ...S.btnSm, background: '#fff', color: '#4f46e5', border: '1px solid #c7d2fe' }}>
                        챗방
                      </button>
                    )}
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
                  </div>
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

      {chatRoomId && (
        <ChatViewModal roomId={chatRoomId} onClose={() => setChatRoomId(null)} />
      )}
    </div>
  )
}

// 신고 증거 — 챗방 메시지 조회 (GET /api/admin/chat-rooms/{roomId}/messages).
function ChatViewModal({ roomId, onClose }) {
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let alive = true
    api.get(`/admin/chat-rooms/${roomId}/messages`)
      .then(r => { if (alive) setData(r.data?.data ?? {}) })
      .catch(() => { if (alive) setData({ messages: [] }) })
      .finally(() => { if (alive) setLoading(false) })
    return () => { alive = false }
  }, [roomId])

  const seller = data?.sellerUserId
  const messages = data?.messages ?? []

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(15,23,42,0.45)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 50 }} onClick={onClose}>
      <div style={{ width: 520, maxWidth: '92vw', maxHeight: '85vh', display: 'flex', flexDirection: 'column', background: '#fff', borderRadius: 16, padding: 20 }} onClick={e => e.stopPropagation()}>
        <div style={{ fontSize: 16, fontWeight: 700, color: '#1e293b', marginBottom: 4 }}>신고된 채팅 내용</div>
        <div style={{ fontSize: 11, color: '#94a3b8', marginBottom: 14, fontFamily: 'monospace' }}>{roomId}</div>
        <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {loading ? (
            <div style={{ color: '#94a3b8', fontSize: 13 }}>불러오는 중...</div>
          ) : messages.length === 0 ? (
            <div style={{ color: '#94a3b8', fontSize: 13 }}>메시지가 없습니다.</div>
          ) : messages.map(m => {
            const isSeller = m.senderUserId === seller
            const isSystem = m.messageType === 'SYSTEM'
            return (
              <div key={m.chatMessageId} style={{ alignSelf: isSystem ? 'center' : (isSeller ? 'flex-start' : 'flex-end'), maxWidth: '78%' }}>
                {!isSystem && (
                  <div style={{ fontSize: 10, color: '#94a3b8', marginBottom: 2, textAlign: isSeller ? 'left' : 'right' }}>
                    {isSeller ? '판매자' : '구매자'} · {String(m.createdAt ?? '').split('.')[0].replace('T', ' ').slice(5)}
                  </div>
                )}
                <div style={{
                  fontSize: 13, padding: '8px 12px', borderRadius: 12, lineHeight: 1.4,
                  background: isSystem ? '#f1f5f9' : (isSeller ? '#eef2ff' : '#dbeafe'),
                  color: isSystem ? '#94a3b8' : '#1e293b',
                  fontStyle: isSystem ? 'italic' : 'normal',
                }}>{m.message}</div>
              </div>
            )
          })}
        </div>
        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 16 }}>
          <button onClick={onClose} style={{ fontSize: 13, fontWeight: 600, padding: '9px 18px', borderRadius: 8, border: '1px solid #e2e8f0', background: '#fff', color: '#475569', cursor: 'pointer' }}>닫기</button>
        </div>
      </div>
    </div>
  )
}

function HandleModal({ row, onClose, onDone }) {
  // 대상 타입에 맞는 조치만 노출 — TRADE=거래글 삭제, BOARD_POST=숨김/삭제, BOARD_COMMENT=삭제,
  // BUY_ORDER 는 유저 해석 불가라 경고/정지 숨김. 게시판 글/댓글은 작성자 해석되므로 경고/정지 노출.
  const isTrade = row.targetType === 'TRADE'
  const isBoardPost = row.targetType === 'BOARD_POST'
  const isBoardComment = row.targetType === 'BOARD_COMMENT'
  const hasUser = ['USER', 'TRADE', 'CHAT', 'BOARD_POST', 'BOARD_COMMENT'].includes(row.targetType)
  const decisions = DECISIONS.filter(d => {
    if (d.tradeOnly) return isTrade
    if (d.boardPostOnly) return isBoardPost
    if (d.boardCommentOnly) return isBoardComment
    if (d.needsUser) return hasUser
    return true
  })

  // 이미 처리된 신고면 기존 조치 복원, 아니면 미선택(강제 선택 → 오발송 방지).
  const initial = decisions.some(d => d.key === row.resolutionAction) ? row.resolutionAction : null
  const [decision, setDecision] = useState(initial)
  const [memo, setMemo] = useState(row.adminMemo ?? '')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')

  const chosen = DECISIONS.find(d => d.key === decision) ?? null
  const isDanger = chosen?.tone === 'danger'

  // 게시판 신고 — 원문·문맥(신고 당시 snapshot + 현재) 자동 로딩. 조치별 활성 조건은 actionEnabled().
  const isBoardReport = isBoardPost || isBoardComment
  const [context, setContext] = useState(null)
  const [contextLoading, setContextLoading] = useState(isBoardReport)
  const [contextError, setContextError] = useState(false)
  const ctxBoxStyle = { background: '#f8fafc', borderRadius: 10, padding: '12px 14px', fontSize: 13, lineHeight: 1.6 }

  // 조치별 활성 — ★백엔드 계약: soft-delete 도 available=true + post/comment.deleted=true 로 옴.
  //   숨김=글 존재·미삭제·미숨김 / 삭제=글(또는 대상 댓글) 존재·미삭제 / 경고·정지=snapshot 또는 현재 증거 존재
  //   (현재 삭제됐어도 증거 있으면 제재) / 기각·보류=항상. 로딩/오류(context 미로딩)=잠금.
  function actionEnabled(key) {
    if (!isBoardReport || key === 'DISMISS' || key === 'NONE') return true
    if (!context) return false
    const post = context.post
    const targetComment = context.thread?.comments?.find(c => c.target)
    switch (key) {
      case 'HIDE_BOARD_POST': return !!post && !post.deleted && !post.hidden
      case 'DELETE_BOARD_POST': return !!post && !post.deleted
      case 'DELETE_BOARD_COMMENT': return !!targetComment && !targetComment.deleted
      case 'WARN_USER':
      case 'SUSPEND_USER': return !!(context.available || context.snapshotAvailable)
      default: return true
    }
  }

  async function loadContext() {
    setContextLoading(true)
    setContextError(false)
    try {
      const r = await api.get(`/admin/reports/${row.reportId}/target-context`)
      setContext(r.data?.data ?? null)
    } catch {
      setContextError(true)
    } finally {
      setContextLoading(false)
    }
  }
  // 마운트 시 원문 1회 로딩(fetch-on-mount). set-state-in-effect 는 repo 전역 패턴과 동일 — 명시 disable.
  useEffect(() => { if (isBoardReport) loadContext() }, []) // eslint-disable-line react-hooks/exhaustive-deps, react-hooks/set-state-in-effect

  async function submit() {
    if (!chosen) return
    if (!actionEnabled(chosen.key)) return // 조치별 활성 조건 미충족(원문·증거 없음) 차단
    if (isDanger) {
      if (!confirm(`'${chosen.label}' 조치를 실행할까요? 되돌릴 수 없어요.`)) return
    } else if (chosen.key === 'WARN_USER') {
      if (!confirm('이 유저에게 경고를 발급할까요? (누적 3회 시 자동 정지)')) return
    }
    setSubmitting(true)
    setError('')
    try {
      // 단일 조치 → status + resolutionAction 동시 파생 전송. 백엔드 계약은 그대로.
      await api.patch(`/admin/reports/${row.reportId}/status`, {
        status: chosen.status,
        adminMemo: memo.trim() || null,
        resolutionAction: chosen.key,
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
        width: 520, maxHeight: '90vh', overflowY: 'auto', background: '#fff', borderRadius: 16,
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
          {row.targetSummary ? ` · 대상: ${row.targetSummary}` : ''}
        </div>

        {row.detail && (
          <div style={{
            background: '#f8fafc', borderRadius: 10, padding: '12px 14px',
            marginBottom: 20, fontSize: 13, color: '#475569', lineHeight: 1.6, maxHeight: 120, overflow: 'auto',
          }}>{row.detail}</div>
        )}

        {isBoardReport && (
          <div style={{ marginBottom: 20 }}>
            <label style={{ fontSize: 12, fontWeight: 700, color: '#64748b', display: 'block', marginBottom: 8 }}>원문 및 문맥</label>
            {contextLoading ? (
              <div style={{ ...ctxBoxStyle, color: '#94a3b8' }}>원문을 불러오는 중...</div>
            ) : contextError ? (
              <div style={{ padding: '12px 14px', borderRadius: 10, background: '#fef2f2', border: '1px solid #fecaca', fontSize: 12, color: '#dc2626', lineHeight: 1.6 }}>
                원문을 불러오지 못했어요. 삭제·숨김·제재는 원문 확인 후 가능해요.{' '}
                <button onClick={loadContext} style={{ border: 'none', background: 'none', color: '#4f46e5', fontWeight: 700, cursor: 'pointer', padding: 0 }}>재시도</button>
              </div>
            ) : context ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                <div>
                  <div style={{ fontSize: 11.5, fontWeight: 700, color: '#475569', marginBottom: 6 }}>
                    신고 당시 내용
                    {context.changedSinceReport && <span style={{ marginLeft: 6 }}><CtxBadge text="신고 후 수정됨" tone="danger" /></span>}
                  </div>
                  {context.snapshotAvailable ? (
                    <>
                      <BoardContextView ctx={snapshotToCtx(context.reportedSnapshot)} />
                      <ImageStrip urls={context.snapshotImageUrls} count={context.snapshotImageCount} />
                    </>
                  ) : (
                    <div style={{ ...ctxBoxStyle, color: '#94a3b8' }}>{snapshotNote(context.snapshotStatus)}</div>
                  )}
                </div>
                <div>
                  <div style={{ fontSize: 11.5, fontWeight: 700, color: '#475569', marginBottom: 6 }}>현재 내용</div>
                  {context.available ? (
                    <>
                      <BoardContextView ctx={context} />
                      <ImageStrip urls={context.currentImageUrls} count={(context.currentImageUrls || []).length} />
                    </>
                  ) : (
                    <div style={{ ...ctxBoxStyle, color: '#94a3b8' }}>현재 콘텐츠가 삭제되었거나 없습니다.</div>
                  )}
                </div>
              </div>
            ) : null}
          </div>
        )}

        <label style={{ fontSize: 12, fontWeight: 700, color: '#64748b', display: 'block', marginBottom: 8 }}>조치 선택</label>
        {isBoardReport && !context && (
          <div style={{ fontSize: 11, color: '#c2410c', marginBottom: 8 }}>※ 원문 확인 후 조치를 선택할 수 있어요.</div>
        )}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginBottom: 20 }}>
          {decisions.map(d => {
            const locked = !actionEnabled(d.key)
            const sel = decision === d.key
            const t = TONE[d.tone]
            return (
              <button key={d.key} disabled={locked}
                onClick={() => !locked && setDecision(d.key)}
                title={locked ? '원문 확인 후 가능' : undefined}
                style={{
                textAlign: 'left', padding: '12px 14px', borderRadius: 10,
                background: sel ? t.bg : '#fff',
                border: `1.5px solid ${sel ? t.sel : '#e2e8f0'}`,
                cursor: locked ? 'not-allowed' : 'pointer', opacity: locked ? 0.45 : 1, transition: 'all 0.1s',
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span style={{
                    width: 16, height: 16, borderRadius: 99, flexShrink: 0, boxSizing: 'border-box',
                    border: `5px solid ${sel ? t.sel : '#cbd5e1'}`, background: '#fff',
                  }} />
                  <span style={{ fontSize: 14, fontWeight: 700, color: sel ? t.sel : '#1e293b' }}>{d.label}</span>
                </div>
                <div style={{ fontSize: 12, color: '#94a3b8', marginTop: 4, marginLeft: 24, lineHeight: 1.4 }}>{d.desc}</div>
              </button>
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
          <button onClick={submit} disabled={submitting || !chosen} style={{
            flex: 2, padding: '11px', borderRadius: 10,
            background: (submitting || !chosen) ? '#cbd5e1' : (isDanger ? '#dc2626' : '#4f46e5'),
            color: '#fff', fontSize: 13, fontWeight: 600, border: 'none',
            cursor: (submitting || !chosen) ? 'not-allowed' : 'pointer',
          }}>
            {submitting ? '처리 중...' : (chosen ? chosen.label : '조치를 선택하세요')}
          </button>
        </div>
      </div>
    </div>
  )
}

// 신고 원문/문맥 배지 — 기존 STATUS/TONE 팔레트 재사용(새 디자인 체계 X).
function CtxBadge({ text, tone }) {
  const c = {
    warn:   { bg: '#fff7ed', color: '#c2410c', border: '#fed7aa' },
    danger: { bg: '#fef2f2', color: '#dc2626', border: '#fecaca' },
    muted:  { bg: '#f1f5f9', color: '#94a3b8', border: '#e2e8f0' },
  }[tone] ?? { bg: '#f1f5f9', color: '#64748b', border: '#e2e8f0' }
  return (
    <span style={{ fontSize: 10, fontWeight: 700, padding: '1px 6px', borderRadius: 99,
      background: c.bg, color: c.color, border: `1px solid ${c.border}`, whiteSpace: 'nowrap' }}>{text}</span>
  )
}

// snapshot 미표시 사유 안내 — null(LEGACY)만 '이전 신고', 미지원 버전·손상은 구분(같은 null 로 합치지 않음).
function snapshotNote(status) {
  if (status === 'LEGACY_NOT_CAPTURED') return '이전 신고로 신고 당시 원문이 저장되지 않았습니다.'
  if (status === 'UNSUPPORTED_VERSION') return '지원하지 않는 버전의 신고 증거입니다. 시스템 점검이 필요합니다.'
  if (status === 'INVALID') return '신고 당시 증거가 손상되어 표시할 수 없습니다.'
  return '신고 증거 상태를 확인할 수 없습니다.' // 알 수 없는 status(배포 순서 엇갈림 등) — 이전 신고로 단정 금지
}

// 신고 당시 snapshot(ReportedSnapshot) → BoardContextView 가 쓰는 {post, thread} 형태로 변환(렌더 재사용).
// secure proxy 이미지(/api/images/secure/..)를 admin 토큰으로 blob 다운로드 → objectURL. raw storage key 미노출.
function AuthImg({ url, size = 72 }) {
  const [src, setSrc] = useState(null)
  const [err, setErr] = useState(false)
  useEffect(() => {
    let revoked = false
    let objectUrl = null
    api.get(url.replace(/^\/api/, ''), { responseType: 'blob' })
      .then(r => { if (!revoked) { objectUrl = URL.createObjectURL(r.data); setSrc(objectUrl) } })
      .catch(() => { if (!revoked) setErr(true) })
    return () => { revoked = true; if (objectUrl) URL.revokeObjectURL(objectUrl) }
  }, [url])
  const box = { width: size, height: size, borderRadius: 8, objectFit: 'cover', border: '1px solid #e2e8f0', background: '#f1f5f9' }
  if (err) return <div style={{ ...box, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#94a3b8', fontSize: 10 }}>이미지</div>
  if (!src) return <div style={box} />
  return <img src={src} alt="" style={box} />
}

function ImageStrip({ urls, count }) {
  if (!count) return null
  return (
    <div style={{ marginTop: 8 }}>
      <div style={{ fontSize: 11, color: '#64748b', marginBottom: 4 }}>첨부 이미지 {count}장</div>
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
        {(urls || []).map((u, i) => <AuthImg key={i} url={u} />)}
      </div>
    </div>
  )
}

function snapshotToCtx(snap) {
  if (!snap) return { post: null, thread: null }
  if (snap.targetType === 'BOARD_POST') {
    return { post: { title: snap.title, content: snap.content, authorLabel: snap.authorLabel, hidden: false, deleted: false }, thread: null }
  }
  return {
    post: snap.postTitle ? { title: snap.postTitle, content: '', authorLabel: '', hidden: false, deleted: false } : null,
    thread: { comments: (snap.comments || []).map(c => ({ ...c, target: c.commentId === snap.targetCommentId })) },
  }
}

// 게시판 신고 원문·문맥 뷰 — ChatViewModal 스타일(스크롤 영역·말풍선) 재사용. 신고 대상 강조 + 숨김/삭제 배지.
function BoardContextView({ ctx }) {
  const post = ctx.post
  return (
    <div style={{ background: '#f8fafc', borderRadius: 10, padding: '12px 14px', maxHeight: 260, overflow: 'auto', border: '1px solid #f1f5f9' }}>
      {post && (
        <div style={{ marginBottom: ctx.thread ? 12 : 0 }}>
          <div style={{ display: 'flex', gap: 6, alignItems: 'center', flexWrap: 'wrap', marginBottom: 4 }}>
            <span style={{ fontWeight: 700, color: '#1e293b', fontSize: 13 }}>{post.title || '(제목 없음)'}</span>
            {post.hidden && <CtxBadge text="숨김" tone="warn" />}
            {post.deleted && <CtxBadge text="삭제됨" tone="danger" />}
          </div>
          <div style={{ fontSize: 12, color: '#475569', whiteSpace: 'pre-wrap', lineHeight: 1.6 }}>{post.content}</div>
          <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 4 }}>{post.authorLabel}</div>
        </div>
      )}
      {ctx.thread && (
        <div style={{ borderTop: post ? '1px solid #e2e8f0' : 'none', paddingTop: post ? 10 : 0, display: 'flex', flexDirection: 'column', gap: 6 }}>
          {ctx.thread.comments.map(c => (
            <div key={c.commentId} style={{
              padding: '8px 10px', borderRadius: 8, marginLeft: c.parentCommentId ? 16 : 0,
              background: c.target ? '#fef2f2' : '#fff',
              border: `1px solid ${c.target ? '#fecaca' : '#f1f5f9'}`,
            }}>
              <div style={{ display: 'flex', gap: 6, alignItems: 'center', flexWrap: 'wrap' }}>
                <span style={{ fontWeight: 600, fontSize: 11.5, color: '#1e293b' }}>{c.authorLabel}</span>
                {c.target && <CtxBadge text="신고 대상" tone="danger" />}
                {c.deleted && <CtxBadge text="삭제됨" tone="muted" />}
              </div>
              <div style={{ fontSize: 12, color: '#475569', marginTop: 3, whiteSpace: 'pre-wrap' }}>{c.content}</div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
