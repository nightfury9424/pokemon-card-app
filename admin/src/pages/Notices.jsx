// 2026-06 admin — 공지(공식글) 관리. Inquiries/Reports 스타일 일관(흰 카드 + 보라 헤더, 새 디자인 0).
//   list:   GET    /api/board/posts?section=official  (핀 우선 서버 정렬)
//   create: POST   /api/admin/board/posts {type,title,content,isPinned}
//   update/pin: PATCH /api/admin/board/posts/{id} {title,content,isPinned}(null=미변경)
//   delete: DELETE /api/admin/board/posts/{id}
import { useEffect, useState } from 'react'
import { Megaphone, RefreshCw, Plus, X } from 'lucide-react'
import api from '../api'
import ToggleSwitch from '../components/ToggleSwitch'

const TITLE_MAX = 200
const CONTENT_MAX = 10000
const PAGE_SIZE = 20

const TYPES = [
  { value: 'notice', label: '공지' },
  { value: 'event', label: '이벤트' },
  { value: 'patch', label: '업데이트' },
]
const TYPE_LABEL = Object.fromEntries(TYPES.map(t => [t.value, t.label]))
const TYPE_TONE = {
  notice: { bg: '#eef2ff', color: '#4f46e5', border: '#c7d2fe' },
  event:  { bg: '#fff7ed', color: '#c2410c', border: '#fed7aa' },
  patch:  { bg: '#f0fdf4', color: '#16a34a', border: '#bbf7d0' },
}

const S = {
  page:    { padding: '32px 36px', minHeight: '100%', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' },
  header:  { display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24, gap: 12, flexWrap: 'wrap' },
  h1:      { fontSize: 22, fontWeight: 700, color: '#1e293b', letterSpacing: -0.5 },
  sub:     { fontSize: 13, color: '#94a3b8', marginTop: 3 },
  actions: { display: 'flex', alignItems: 'center', gap: 8 },
  card:    { background: '#fff', borderRadius: 16, border: '1px solid #e8edf4', boxShadow: '0 1px 3px rgba(0,0,0,0.04)', overflow: 'hidden' },
  th:      { padding: '12px 16px', fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.6, textAlign: 'left', background: '#f8fafc', borderBottom: '1px solid #f1f5f9', whiteSpace: 'nowrap' },
  td:      { padding: '13px 16px', fontSize: 13, color: '#475569', borderBottom: '1px solid #f8fafc', verticalAlign: 'middle' },
  btnSm:   { fontSize: 11, fontWeight: 600, padding: '5px 10px', borderRadius: 6, border: 'none', cursor: 'pointer', background: '#eef2ff', color: '#4f46e5' },
  btnDanger: { fontSize: 11, fontWeight: 600, padding: '5px 10px', borderRadius: 6, border: 'none', cursor: 'pointer', background: '#fef2f2', color: '#dc2626' },
  refresh: { display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, fontWeight: 600, padding: '8px 14px', borderRadius: 8, border: '1px solid #e2e8f0', background: '#fff', color: '#475569', cursor: 'pointer' },
  primary: { display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, fontWeight: 700, padding: '8px 14px', borderRadius: 8, border: 'none', background: '#4f46e5', color: '#fff', cursor: 'pointer' },
  banner:  { padding: '10px 14px', borderRadius: 10, background: '#fef2f2', border: '1px solid #fecaca', fontSize: 12, color: '#dc2626', marginBottom: 14 },
  pager:   { display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 12, padding: '14px 16px', fontSize: 12, color: '#64748b' },
  pagerBtn:{ fontSize: 12, fontWeight: 600, padding: '6px 12px', borderRadius: 7, border: '1px solid #e2e8f0', background: '#fff', color: '#475569', cursor: 'pointer' },
}

function TypeBadge({ type }) {
  const t = TYPE_TONE[type] ?? TYPE_TONE.notice
  return <span style={{ fontSize: 11, fontWeight: 600, padding: '3px 8px', borderRadius: 99, background: t.bg, color: t.color, border: `1px solid ${t.border}` }}>{TYPE_LABEL[type] ?? type}</span>
}

function fmt(ts) {
  if (!ts) return '-'
  return String(ts).split('.')[0].replace('T', ' ')
}

export default function Notices() {
  const [rows, setRows] = useState([])
  const [total, setTotal] = useState(0)
  const [totalPages, setTotalPages] = useState(0)
  const [page, setPage] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(false)
  const [actionError, setActionError] = useState('')
  const [pinningId, setPinningId] = useState(null)
  const [modal, setModal] = useState(null) // { mode: 'create' | 'edit', row }
  const [commentPost, setCommentPost] = useState(null) // 댓글 모달 대상 게시글

  useEffect(() => { load(page) }, [page])

  async function load(p) {
    setLoading(true)
    setError(false)
    try {
      const r = await api.get('/board/posts', { params: { section: 'official', page: p, size: PAGE_SIZE } })
      const d = r.data?.data ?? {}
      setRows(d.content ?? [])
      setTotal(d.totalElements ?? 0)
      setTotalPages(d.totalPages ?? 0)
    } catch {
      setError(true)
      setRows([])
    } finally {
      setLoading(false)
    }
  }

  async function togglePin(row, next) {
    if (pinningId) return // 처리 중 다른 토글 차단
    setActionError('')
    setPinningId(row.id)
    try {
      await api.patch('/admin/board/posts/' + row.id, { isPinned: next }) // 핀만 변경(title/content null=미변경)
      await load(page) // ★서버 핀-우선 정렬로 재동기화(낙관적 갱신 안 함 → 실패 시 자동으로 이전 상태 유지)
    } catch (e) {
      setActionError(e.response?.data?.message ?? '고정 상태를 변경하지 못했어요.')
    } finally {
      setPinningId(null)
    }
  }

  async function remove(row) {
    if (!confirm(`'${row.title}' 공지를 삭제할까요? 되돌릴 수 없어요.`)) return // 기존 관리자 위험 확인 패턴
    setActionError('')
    try {
      await api.delete('/admin/board/posts/' + row.id)
      reloadAfterRemove()
    } catch (e) {
      if (e.response?.status === 404) {
        reloadAfterRemove() // 이미 삭제됨 → 목록 갱신(빈 페이지면 이전으로)
        setActionError('이미 삭제된 공지예요. 목록을 갱신했어요.')
      } else {
        setActionError(e.response?.data?.message ?? '삭제하지 못했어요.') // 행 유지
      }
    }
  }

  // 마지막 남은 행을 삭제하면 현재 페이지가 비므로 이전 페이지로(page 0 은 빈 상태 표시). setPage→useEffect 가 load.
  function reloadAfterRemove() {
    if (rows.length === 1 && page > 0) setPage(p => p - 1)
    else load(page)
  }

  return (
    <div style={S.page}>
      <div style={S.header}>
        <div>
          <h1 style={S.h1}><Megaphone size={20} style={{ verticalAlign: -3, marginRight: 8 }} />공지 관리</h1>
          <div style={S.sub}>전체 {total}건</div>
        </div>
        <div style={S.actions}>
          <button style={S.refresh} onClick={() => load(page)} disabled={loading}>
            <RefreshCw size={14} style={{ animation: loading ? 'spin 1s linear infinite' : 'none' }} /> 새로고침
          </button>
          <button style={S.primary} onClick={() => setModal({ mode: 'create' })}>
            <Plus size={15} /> 새 공지
          </button>
        </div>
      </div>

      {actionError && <div style={S.banner}>{actionError}</div>}

      <div style={S.card}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              <th style={S.th}>타입</th>
              <th style={S.th}>제목</th>
              <th style={S.th}>작성일</th>
              <th style={{ ...S.th, textAlign: 'right' }}>조회</th>
              <th style={{ ...S.th, textAlign: 'right' }}>댓글</th>
              <th style={{ ...S.th, textAlign: 'center' }}>상단 고정</th>
              <th style={{ ...S.th, textAlign: 'right' }}>관리</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td style={S.td} colSpan={7}>불러오는 중...</td></tr>
            ) : error ? (
              <tr><td style={S.td} colSpan={7}>
                공지를 불러오지 못했어요.{' '}
                <button onClick={() => load(page)} style={{ border: 'none', background: 'none', color: '#4f46e5', fontWeight: 700, cursor: 'pointer', padding: 0 }}>재시도</button>
              </td></tr>
            ) : rows.length === 0 ? (
              <tr><td style={S.td} colSpan={7}>등록된 공지가 없습니다.</td></tr>
            ) : rows.map(r => (
              <tr key={r.id}>
                <td style={S.td}><TypeBadge type={r.type} /></td>
                <td style={{ ...S.td, color: '#1e293b', fontWeight: 600, maxWidth: 380, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{r.title}</td>
                <td style={{ ...S.td, whiteSpace: 'nowrap' }}>{fmt(r.createdAt)}</td>
                <td style={{ ...S.td, textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{r.viewCount ?? 0}</td>
                <td style={{ ...S.td, textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{r.commentCount ?? 0}</td>
                <td style={{ ...S.td, textAlign: 'center' }}>
                  <ToggleSwitch
                    checked={!!r.isPinned}
                    loading={pinningId === r.id}
                    disabled={pinningId != null && pinningId !== r.id}
                    onChange={(next) => togglePin(r, next)}
                    ariaLabel={`${r.title} 상단 고정`}
                    id={`pin-${r.id}`}
                  />
                </td>
                <td style={{ ...S.td, textAlign: 'right', whiteSpace: 'nowrap' }}>
                  <button style={S.btnSm} onClick={() => setCommentPost(r)}>댓글</button>{' '}
                  <button style={S.btnSm} onClick={() => setModal({ mode: 'edit', row: r })}>수정</button>{' '}
                  <button style={S.btnDanger} onClick={() => remove(r)}>삭제</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {!loading && !error && totalPages > 1 && (
          <div style={S.pager}>
            <button style={{ ...S.pagerBtn, opacity: page <= 0 ? 0.4 : 1, cursor: page <= 0 ? 'default' : 'pointer' }}
              disabled={page <= 0} onClick={() => setPage(p => Math.max(0, p - 1))}>이전</button>
            <span>{page + 1} / {totalPages}</span>
            <button style={{ ...S.pagerBtn, opacity: page >= totalPages - 1 ? 0.4 : 1, cursor: page >= totalPages - 1 ? 'default' : 'pointer' }}
              disabled={page >= totalPages - 1} onClick={() => setPage(p => Math.min(totalPages - 1, p + 1))}>다음</button>
          </div>
        )}
      </div>

      {modal && (
        <ComposeModal
          mode={modal.mode}
          row={modal.row}
          onClose={() => setModal(null)}
          onDone={() => {
            const created = modal.mode === 'create'
            setModal(null)
            if (created && page !== 0) setPage(0) // 작성 → page 0 으로 이동(useEffect 가 load). 이미 0 이면 아래서 직접 load.
            else load(page)
          }}
        />
      )}

      {commentPost && (
        <CommentsModal post={commentPost} onClose={() => setCommentPost(null)} />
      )}
    </div>
  )
}

// 공지 댓글 모달 — 게시글 상세(GET /board/posts/{id})의 comments(body 포함) 표시 + 운영팀 댓글 작성.
function CommentsModal({ post, onClose }) {
  const [comments, setComments] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(false)
  const [text, setText] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [replyTo, setReplyTo] = useState(null) // { id(=parentCommentId), author } — 답글 대상

  useEffect(() => { loadComments() }, [])

  async function loadComments() {
    setLoading(true); setError(false)
    try {
      const r = await api.get('/board/posts/' + post.id)
      setComments(r.data?.data?.comments ?? [])
    } catch { setError(true) } finally { setLoading(false) }
  }

  async function submit() {
    const body = text.trim()
    if (!body || submitting) return
    setSubmitting(true)
    try {
      const payload = { content: body }
      if (replyTo?.id) payload.parentCommentId = replyTo.id // 대댓글(1단 답글)
      await api.post('/admin/board/posts/' + post.id + '/comments', payload)
      setText('')
      setReplyTo(null)
      await loadComments()
    } catch (e) {
      alert('댓글 등록 실패: ' + (e?.response?.data?.message || e.message))
    } finally { setSubmitting(false) }
  }

  const fmtT = (iso) => {
    try {
      const d = new Date(iso)
      const p = n => String(n).padStart(2, '0')
      return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`
    } catch { return '' }
  }

  const renderComment = (c, depth = 0) => (
    <div key={c.id} style={{ marginLeft: depth * 18, padding: '10px 0', borderBottom: '1px solid #f1f5f9' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
        <span style={{ fontWeight: 700, fontSize: 13, color: '#1e293b' }}>{c.author || '(알 수 없음)'}</span>
        {c.isAdmin && <span style={{ fontSize: 11, color: '#4f46e5', fontWeight: 700 }}>운영팀</span>}
        <span style={{ fontSize: 11, color: '#94a3b8' }}>{fmtT(c.createdAt)}</span>
      </div>
      <div style={{ fontSize: 13, color: '#334155', whiteSpace: 'pre-wrap', lineHeight: 1.5 }}>
        {c.body != null && c.body !== '' ? c.body : <span style={{ color: '#94a3b8', fontStyle: 'italic' }}>(삭제되었거나 내용 없음)</span>}
      </div>
      {c.replyTargetCommentId && (
        <button onClick={() => setReplyTo({ id: c.replyTargetCommentId, author: c.author })}
          style={{ marginTop: 4, background: 'none', border: 'none', padding: 0, cursor: 'pointer', color: '#4f46e5', fontSize: 12, fontWeight: 600 }}>답글</button>
      )}
      {(c.replies ?? []).map(rep => renderComment(rep, depth + 1))}
    </div>
  )

  return (
    <div onClick={onClose} style={{ position: 'fixed', inset: 0, background: 'rgba(15,23,42,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100, padding: 16 }}>
      <div onClick={e => e.stopPropagation()} style={{ width: 560, maxWidth: '100%', maxHeight: '90vh', display: 'flex', flexDirection: 'column', background: '#fff', borderRadius: 16, padding: 24, boxShadow: '0 20px 50px rgba(0,0,0,0.2)' }}>
        <div style={{ display: 'flex', alignItems: 'center', marginBottom: 12 }}>
          <div style={{ fontSize: 16, fontWeight: 800, color: '#1e293b', flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>댓글 — {post.title}</div>
          <button onClick={onClose} style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#94a3b8' }}><X size={20} /></button>
        </div>
        <div style={{ flex: 1, overflowY: 'auto', minHeight: 120 }}>
          {loading ? <div style={{ color: '#94a3b8', fontSize: 13, padding: 20, textAlign: 'center' }}>불러오는 중…</div>
            : error ? <div style={{ color: '#dc2626', fontSize: 13, padding: 20, textAlign: 'center' }}>불러오기 실패</div>
            : comments.length === 0 ? <div style={{ color: '#94a3b8', fontSize: 13, padding: 20, textAlign: 'center' }}>아직 댓글이 없습니다</div>
            : comments.map(c => renderComment(c))}
        </div>
        <div style={{ marginTop: 12, borderTop: '1px solid #e2e8f0', paddingTop: 12 }}>
          {replyTo && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6, fontSize: 12, color: '#475569' }}>
              <span>↳ <b>{replyTo.author}</b> 님에게 답글</span>
              <button onClick={() => setReplyTo(null)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#94a3b8', fontSize: 12 }}>취소</button>
            </div>
          )}
          <textarea value={text} onChange={e => setText(e.target.value)} placeholder={replyTo ? '운영팀 답글 입력 (Enter 등록 · Shift+Enter 줄바꿈)' : '운영팀 댓글 입력 (Enter 등록 · Shift+Enter 줄바꿈)'} rows={2}
            onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit() } }}
            style={{ width: '100%', boxSizing: 'border-box', border: '1px solid #cbd5e1', borderRadius: 8, padding: 10, fontSize: 13, resize: 'vertical' }} />
          <div style={{ display: 'flex', alignItems: 'center', marginTop: 8 }}>
            <div style={{ fontSize: 11, color: '#94a3b8', flex: 1 }}>운영팀으로 작성됩니다 — 앱 공지 상세에 운영팀 배지로 노출.</div>
            <button onClick={submit} disabled={submitting || !text.trim()} style={{ ...S.primary, opacity: (submitting || !text.trim()) ? 0.5 : 1 }}>{submitting ? '등록 중…' : '등록'}</button>
          </div>
        </div>
      </div>
    </div>
  )
}

function ComposeModal({ mode, row, onClose, onDone }) {
  const [type, setType] = useState(row?.type ?? 'notice')
  const [title, setTitle] = useState(row?.title ?? '')
  const [content, setContent] = useState(row?.body ?? '')
  const [pinned, setPinned] = useState(row?.isPinned ?? false)
  const [submitting, setSubmitting] = useState(false)
  const [err, setErr] = useState('')

  const titleTrim = title.trim()
  const contentTrim = content.trim()
  const overTitle = title.length > TITLE_MAX
  const overContent = content.length > CONTENT_MAX
  const valid = titleTrim !== '' && contentTrim !== '' && !overTitle && !overContent

  function close() {
    if (submitting) return // 제출 중 닫기 방지
    onClose()
  }

  async function submit() {
    if (submitting) return // 중복 제출 차단
    if (!valid) { setErr('제목과 내용을 입력해주세요.'); return }
    setSubmitting(true)
    setErr('')
    try {
      if (mode === 'create') {
        await api.post('/admin/board/posts', { type, title: titleTrim, content: contentTrim, isPinned: pinned })
      } else {
        await api.patch('/admin/board/posts/' + row.id, { title: titleTrim, content: contentTrim, isPinned: pinned })
      }
      onDone()
    } catch (e) {
      setErr(e.response?.data?.message ?? '저장하지 못했어요. 다시 시도해주세요.') // 입력값 보존
    } finally {
      setSubmitting(false)
    }
  }

  const label = { fontSize: 12, fontWeight: 700, color: '#64748b', display: 'block', marginBottom: 8 }
  const inputBase = { width: '100%', padding: '10px 12px', borderRadius: 10, border: '1px solid #e2e8f0', fontSize: 14, color: '#1e293b', outline: 'none', fontFamily: 'inherit' }

  return (
    <div onClick={close} style={{ position: 'fixed', inset: 0, background: 'rgba(15,23,42,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100, padding: 16 }}>
      <div onClick={e => e.stopPropagation()} style={{ width: 560, maxWidth: '100%', maxHeight: '90vh', overflowY: 'auto', background: '#fff', borderRadius: 16, padding: 28, boxShadow: '0 20px 50px rgba(0,0,0,0.2)' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 20 }}>
          <h2 style={{ fontSize: 18, fontWeight: 700, color: '#1e293b' }}>{mode === 'create' ? '새 공지 작성' : '공지 수정'}</h2>
          <button onClick={close} disabled={submitting} style={{ background: 'none', border: 'none', cursor: submitting ? 'not-allowed' : 'pointer', color: '#94a3b8' }}><X size={20} /></button>
        </div>

        <div style={{ marginBottom: 18 }}>
          <label style={label}>타입</label>
          {mode === 'create' ? (
            <div style={{ display: 'flex', gap: 8 }}>
              {TYPES.map(t => {
                const sel = type === t.value
                return (
                  <button key={t.value} type="button" onClick={() => setType(t.value)} style={{
                    fontSize: 13, fontWeight: 600, padding: '8px 16px', borderRadius: 8, cursor: 'pointer',
                    border: `1.5px solid ${sel ? '#4f46e5' : '#e2e8f0'}`,
                    background: sel ? '#eef2ff' : '#fff', color: sel ? '#4f46e5' : '#64748b',
                  }}>{t.label}</button>
                )
              })}
            </div>
          ) : (
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <TypeBadge type={type} />
              <span style={{ fontSize: 11, color: '#94a3b8' }}>유형은 작성 후 변경할 수 없어요</span>
            </div>
          )}
        </div>

        <div style={{ marginBottom: 18 }}>
          <label style={label}>제목</label>
          <input value={title} onChange={e => setTitle(e.target.value)} placeholder="공지 제목"
            style={{ ...inputBase, borderColor: overTitle ? '#fca5a5' : '#e2e8f0' }} />
          <div style={{ textAlign: 'right', fontSize: 11, color: overTitle ? '#dc2626' : '#94a3b8', marginTop: 4 }}>{title.length} / {TITLE_MAX}</div>
        </div>

        <div style={{ marginBottom: 18 }}>
          <label style={label}>내용</label>
          <textarea value={content} onChange={e => setContent(e.target.value)} placeholder="공지 내용" rows={9}
            style={{ ...inputBase, resize: 'vertical', lineHeight: 1.6, borderColor: overContent ? '#fca5a5' : '#e2e8f0' }} />
          <div style={{ textAlign: 'right', fontSize: 11, color: overContent ? '#dc2626' : '#94a3b8', marginTop: 4 }}>{content.length} / {CONTENT_MAX}</div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 22 }}>
          <ToggleSwitch checked={pinned} onChange={setPinned} disabled={submitting} ariaLabel="상단 고정" id="compose-pin" />
          <span style={{ fontSize: 13, color: '#475569' }}>상단 고정</span>
        </div>

        {err && <div style={{ ...S.banner, marginBottom: 16 }}>{err}</div>}

        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10 }}>
          <button onClick={close} disabled={submitting} style={{ fontSize: 13, fontWeight: 600, padding: '10px 18px', borderRadius: 10, border: '1px solid #e2e8f0', background: '#fff', color: '#475569', cursor: submitting ? 'not-allowed' : 'pointer' }}>취소</button>
          <button onClick={submit} disabled={submitting || !valid} style={{ fontSize: 13, fontWeight: 700, padding: '10px 18px', borderRadius: 10, border: 'none', background: (submitting || !valid) ? '#c7d2fe' : '#4f46e5', color: '#fff', cursor: (submitting || !valid) ? 'not-allowed' : 'pointer', display: 'flex', alignItems: 'center', gap: 6 }}>
            {submitting && <RefreshCw size={13} style={{ animation: 'spin 1s linear infinite' }} />}
            {mode === 'create' ? '등록' : '저장'}
          </button>
        </div>
      </div>
    </div>
  )
}
