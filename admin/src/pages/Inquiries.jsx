// 2026-06 admin — 고객 문의 처리 페이지 (메일 → DB 전환).
//   backend: GET /api/admin/inquiries + PATCH /api/admin/inquiries/{id}/reply
//   Reports.jsx 스타일 일관 — 흰 카드 + 보라 헤더.

import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Mail, RefreshCw, Send } from 'lucide-react'
import api from '../api'

// 카드추가요청 문의 content(라벨 구조화) 파싱 → 카드추가 폼 prefill 객체
// content 포맷(앱 inquiry_compose_screen): "카드명: …/언어: 한국판|일본판|미국판/수록팩/세트명: …/카드 번호: …/레어도: …/참고 링크: …"
function parseCardAddRequest(content) {
  const f = {}
  for (const line of (content || '').split('\n')) {
    const i = line.indexOf(':')
    if (i > 0) f[line.slice(0, i).trim()] = line.slice(i + 1).trim()
  }
  const lang = f['언어'] || ''
  const language = lang.includes('일본') ? 'JP'
    : (lang.includes('미국') || lang.includes('영')) ? 'EN' : 'KO'
  return {
    name: f['카드명'] || '',
    language,
    setName: f['수록팩/세트명'] || '',
    collectionNumber: f['카드 번호'] || '',
    rarity: f['레어도'] || '',
    refLink: f['참고 링크'] || '',
  }
}

const S = {
  page:   { padding: '32px 36px', minHeight: '100%', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' },
  header: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 },
  h1:     { fontSize: 22, fontWeight: 700, color: '#1e293b', letterSpacing: -0.5 },
  sub:    { fontSize: 13, color: '#94a3b8', marginTop: 3 },
  card:   { background: '#fff', borderRadius: 16, border: '1px solid #e8edf4', boxShadow: '0 1px 3px rgba(0,0,0,0.04)', overflow: 'hidden' },
  th:     { padding: '12px 16px', fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.6, textAlign: 'left', background: '#f8fafc', borderBottom: '1px solid #f1f5f9' },
  td:     { padding: '13px 16px', fontSize: 13, color: '#475569', borderBottom: '1px solid #f8fafc', verticalAlign: 'top' },
  btnSm:  { fontSize: 11, fontWeight: 600, padding: '5px 10px', borderRadius: 6, border: 'none', cursor: 'pointer', background: '#eef2ff', color: '#4f46e5' },
  refresh:{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, fontWeight: 600, padding: '8px 14px', borderRadius: 8, border: '1px solid #e2e8f0', background: '#fff', color: '#475569', cursor: 'pointer' },
}

const CATEGORY_LABEL = {
  cardAddRequest: '카드 추가', price: '시세/가격', trade: '거래/채팅',
  account: '계정/닉네임', bug: '버그', feature: '기능 제안', etc: '기타',
  SUSPENSION_APPEAL: '정지 이의신청',
}

const STATUS_MAP = {
  OPEN:     { label: '대기', bg: '#fff7ed', color: '#c2410c', border: '#fed7aa' },
  ANSWERED: { label: '답변완료', bg: '#f0fdf4', color: '#16a34a', border: '#bbf7d0' },
  CLOSED:   { label: '종료', bg: '#f8fafc', color: '#64748b', border: '#e2e8f0' },
}

function StatusBadge({ status }) {
  const s = STATUS_MAP[status] ?? STATUS_MAP.OPEN
  return (
    <span style={{ fontSize: 11, fontWeight: 600, padding: '3px 8px', borderRadius: 99, background: s.bg, color: s.color, border: `1px solid ${s.border}` }}>{s.label}</span>
  )
}

export default function Inquiries() {
  const [rows, setRows] = useState([])
  const [openCount, setOpenCount] = useState(0)
  const [loading, setLoading] = useState(true)
  const [modalRow, setModalRow] = useState(null)
  const [cat, setCat] = useState('')   // 분류 필터 ('' = 전체)

  useEffect(() => { load() }, [cat])

  async function load() {
    setLoading(true)
    try {
      // 분류 선택 시 그 분류만, 전체면 정지 이의신청(별도 /appeals)만 제외.
      const params = cat ? { category: cat } : { excludeCategory: 'SUSPENSION_APPEAL' }
      const r = await api.get('/admin/inquiries', { params })
      setRows(r.data?.data?.content ?? [])
      setOpenCount(r.data?.data?.openCount ?? 0)
    } catch {
      setRows([])
    } finally {
      setLoading(false)
    }
  }

  function fmt(ts) {
    if (!ts) return '-'
    return String(ts).split('.')[0].replace('T', ' ')
  }

  return (
    <div style={S.page}>
      <div style={S.header}>
        <div>
          <h1 style={S.h1}><Mail size={20} style={{ verticalAlign: -3, marginRight: 8 }} />고객 문의</h1>
          <div style={S.sub}>미처리 {openCount}건 · 전체 {rows.length}건</div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <select value={cat} onChange={e => setCat(e.target.value)}
            style={{ fontSize: 13, fontWeight: 600, padding: '8px 12px', borderRadius: 8, border: '1px solid #e2e8f0', background: '#fff', color: '#475569', cursor: 'pointer', fontFamily: 'inherit' }}>
            <option value="">전체 분류</option>
            {Object.entries(CATEGORY_LABEL).filter(([k]) => k !== 'SUSPENSION_APPEAL').map(([k, v]) => (
              <option key={k} value={k}>{v}</option>
            ))}
          </select>
          <button style={S.refresh} onClick={load} disabled={loading}>
            <RefreshCw size={14} /> 새로고침
          </button>
        </div>
      </div>

      <div style={S.card}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              <th style={S.th}>분류</th>
              <th style={S.th}>제목</th>
              <th style={S.th}>작성자</th>
              <th style={S.th}>상태</th>
              <th style={S.th}>작성일</th>
              <th style={S.th}>처리</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td style={S.td} colSpan={6}>불러오는 중...</td></tr>
            ) : rows.length === 0 ? (
              <tr><td style={S.td} colSpan={6}>문의가 없습니다.</td></tr>
            ) : rows.map(r => (
              <tr key={r.inquiryId}>
                <td style={S.td}>{CATEGORY_LABEL[r.category] ?? r.category}</td>
                <td style={{ ...S.td, color: '#1e293b', fontWeight: 600, maxWidth: 320 }}>{r.title}</td>
                <td style={S.td}>{r.nickname || <span style={{ fontFamily: 'monospace', fontSize: 11, color: '#94a3b8' }}>{r.userId}</span>}</td>
                <td style={S.td}><StatusBadge status={r.status} /></td>
                <td style={{ ...S.td, whiteSpace: 'nowrap' }}>{fmt(r.createdAt)}</td>
                <td style={S.td}>
                  <button style={S.btnSm} onClick={() => setModalRow(r)}>
                    {r.status === 'OPEN' ? '답변' : '보기'}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {modalRow && (
        <ReplyModal row={modalRow} onClose={() => setModalRow(null)} onDone={() => { setModalRow(null); load() }} />
      )}
    </div>
  )
}

function ReplyModal({ row, onClose, onDone }) {
  const navigate = useNavigate()
  const [reply, setReply] = useState(row.adminReply ?? '')
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState('')
  // 카드 추가 요청 감지 — 카테고리 또는 제목/내용(앱이 etc 로 보내는 케이스도 커버).
  const isCardAdd = row.category === 'cardAddRequest'
    || (row.title || '').includes('카드 추가')
    || (row.content || '').includes('카드 추가 요청')

  async function submit() {
    if (!reply.trim()) { setErr('답변 내용을 입력하세요.'); return }
    setSaving(true); setErr('')
    try {
      await api.patch(`/admin/inquiries/${row.inquiryId}/reply`, { reply: reply.trim() })
      onDone()
    } catch {
      setErr('저장 실패. 다시 시도하세요.')
      setSaving(false)
    }
  }

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(15,23,42,0.45)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 50 }} onClick={onClose}>
      <div style={{ width: 540, maxWidth: '92vw', maxHeight: '88vh', overflow: 'auto', background: '#fff', borderRadius: 16, padding: 24 }} onClick={e => e.stopPropagation()}>
        <div style={{ fontSize: 16, fontWeight: 700, color: '#1e293b', marginBottom: 4 }}>{row.title}</div>
        <div style={{ fontSize: 12, color: '#94a3b8', marginBottom: 14 }}>
          {CATEGORY_LABEL[row.category] ?? row.category} · {row.nickname || row.userId}
          {row.contactEmail ? ` · ${row.contactEmail}` : ''}
        </div>
        <div style={{ background: '#f8fafc', border: '1px solid #f1f5f9', borderRadius: 10, padding: 14, fontSize: 13, color: '#475569', whiteSpace: 'pre-wrap', marginBottom: row.category === 'cardAddRequest' ? 10 : 18 }}>
          {row.content}
        </div>
        {row.imageUrls?.length > 0 && (
          <div style={{ marginBottom: 18 }}>
            <div style={{ fontSize: 12, fontWeight: 700, color: '#1e293b', marginBottom: 6 }}>첨부 사진 ({row.imageUrls.length})</div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {row.imageUrls.map((url, i) => (
                <a key={i} href={url} target="_blank" rel="noreferrer">
                  <img src={url} alt={`첨부${i + 1}`} style={{ width: 96, height: 96, objectFit: 'cover', borderRadius: 8, border: '1px solid #e2e8f0', cursor: 'zoom-in' }} />
                </a>
              ))}
            </div>
          </div>
        )}
        {isCardAdd && (
          <div style={{ background: '#eef2ff', border: '1px solid #c7d2fe', borderRadius: 10, padding: '12px 14px', marginBottom: 16 }}>
            <div style={{ fontSize: 12, fontWeight: 700, color: '#4f46e5', marginBottom: 8 }}>카드 추가 요청 처리</div>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              {/* B1: 문의 content 파싱 → 카드추가 폼 prefill */}
              <button onClick={() => navigate('/cards', { state: { prefillCard: parseCardAddRequest(row.content) } })}
                style={{ fontSize: 12, fontWeight: 600, padding: '7px 12px', borderRadius: 7, border: '1px solid #4f46e5', background: '#4f46e5', color: '#fff', cursor: 'pointer' }}>
                카드 관리에서 추가하기 →
              </button>
              <button onClick={() => setReply('요청하신 카드를 카탈로그에 추가했어요. 앱에서 검색해 확인해 주세요. 소중한 제보 감사합니다!')}
                style={{ fontSize: 12, fontWeight: 600, padding: '7px 12px', borderRadius: 7, border: '1px solid #c7d2fe', background: '#fff', color: '#4f46e5', cursor: 'pointer' }}>
                처리완료 답변 채우기
              </button>
            </div>
            <div style={{ fontSize: 11, color: '#64748b', marginTop: 8 }}>
              카드 관리에서 직접 추가 후 답변을 등록하면 사용자에게 알림이 가요.
            </div>
          </div>
        )}
        <div style={{ fontSize: 12, fontWeight: 700, color: '#1e293b', marginBottom: 6 }}>관리자 답변</div>
        <textarea
          value={reply}
          onChange={e => setReply(e.target.value)}
          rows={5}
          placeholder="사용자에게 전달할 답변을 입력하세요."
          style={{ width: '100%', boxSizing: 'border-box', borderRadius: 10, border: '1px solid #e2e8f0', padding: 12, fontSize: 13, fontFamily: 'inherit', resize: 'vertical' }}
        />
        {err && <div style={{ color: '#dc2626', fontSize: 12, marginTop: 8 }}>{err}</div>}
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 18 }}>
          <button onClick={onClose} style={{ fontSize: 13, fontWeight: 600, padding: '9px 16px', borderRadius: 8, border: '1px solid #e2e8f0', background: '#fff', color: '#475569', cursor: 'pointer' }}>닫기</button>
          <button onClick={submit} disabled={saving} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, fontWeight: 700, padding: '9px 18px', borderRadius: 8, border: 'none', background: '#4f46e5', color: '#fff', cursor: 'pointer', opacity: saving ? 0.6 : 1 }}>
            <Send size={14} /> {saving ? '저장 중...' : '답변 등록'}
          </button>
        </div>
      </div>
    </div>
  )
}
