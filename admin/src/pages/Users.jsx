import { useEffect, useState } from 'react'
import { Search, ChevronLeft, ChevronRight, Ban, Undo2, AlertTriangle, X, Image as ImageIcon } from 'lucide-react'
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

// 2026-06-07 경고 발급 — 누적 임계치 도달 시 백엔드가 자동 정지. audit log 기록.
async function warnUser(userId) {
  const reason = prompt('경고 사유 (audit log 기록 · 누적 시 자동 정지):')
  if (!reason || !reason.trim()) return false
  if (!confirm(`경고를 발급할까요? 사유: ${reason}`)) return false
  try {
    await api.post(`/admin/users/${userId}/warn`, { reason: reason.trim() })
    return true
  } catch (e) {
    alert(e.response?.data?.message ?? '경고 처리 실패')
    return false
  }
}

// 2026-06-12 탈퇴 audit — 관리자 탈퇴 처리(원본 PII 90일 보존) + 원본 조회.
async function deleteUserAdmin(userId) {
  if (!confirm('이 유저를 탈퇴 처리할까요?\n원본 정보(닉네임/이메일)는 90일간 보존 후 완전 삭제됩니다.')) return false
  try {
    await api.post(`/admin/users/${userId}/delete`, {})
    return true
  } catch (e) {
    alert(e.response?.data?.message ?? '탈퇴 처리 실패')
    return false
  }
}

const fmtDt = (s) => (s ? String(s).slice(0, 19).replace('T', ' ') : '-')

function DRow({ label, children }) {
  return (
    <div style={{ display: 'flex', padding: '8px 0', borderBottom: '1px solid #f4f6fa', fontSize: 13, alignItems: 'center' }}>
      <div style={{ width: 132, color: '#94a3b8', flexShrink: 0 }}>{label}</div>
      <div style={{ color: '#1e293b', wordBreak: 'break-all' }}>{children ?? '-'}</div>
    </div>
  )
}

function Consent({ ok, on = '동의', off = '미동의', at }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
      <span style={{
        fontSize: 11, fontWeight: 600, padding: '2px 9px', borderRadius: 99,
        background: ok ? '#f0fdf4' : '#fef2f2', color: ok ? '#16a34a' : '#dc2626',
        border: `1px solid ${ok ? '#bbf7d0' : '#fecaca'}`,
      }}>{ok ? on : off}</span>
      {ok && at && <span style={{ fontSize: 11, color: '#94a3b8' }}>{fmtDt(at)}</span>}
    </span>
  )
}

// 2026-06-12 유저 상세 모달 — 기본정보 + 약관동의 + 스캔사진(presigned, 동의 유저만, 열람 audit).
function UserDetailModal({ userId, onClose }) {
  const [d, setD] = useState(null)
  const [err, setErr] = useState(null)
  const [scans, setScans] = useState(null)
  const [scanLoading, setScanLoading] = useState(false)
  const [assets, setAssets] = useState(null)
  const [assetLoading, setAssetLoading] = useState(false)
  const [zoom, setZoom] = useState(null)

  useEffect(() => {
    if (!userId) return
    setD(null); setErr(null); setScans(null); setAssets(null); setZoom(null); setScanLoading(false); setAssetLoading(false)
    api.get(`/admin/users/${userId}`)
      .then(r => setD(r.data?.data ?? {}))
      .catch(e => setErr(e.response?.data?.message ?? '조회 실패'))
  }, [userId])

  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  if (!userId) return null

  const loadScans = () => {
    setScanLoading(true)
    api.get(`/admin/users/${userId}/scans`)
      .then(r => setScans(r.data?.data?.scans ?? []))
      .catch(e => alert(e.response?.data?.message ?? '스캔 조회 실패'))
      .finally(() => setScanLoading(false))
  }

  // 등록한 카드(보유 자산) + 등록 시 찍은 실제 사진(asset_images). 학습동의와 무관하게 항상 열람.
  const loadAssets = () => {
    setAssetLoading(true)
    api.get(`/admin/users/${userId}/assets`)
      .then(r => setAssets(r.data?.data?.assets ?? []))
      .catch(e => alert(e.response?.data?.message ?? '등록카드 조회 실패'))
      .finally(() => setAssetLoading(false))
  }

  const deleted = d?.deleted
  const scanCount = d?.scanCaptureCount ?? 0

  return (
    <div onClick={onClose} style={{
      position: 'fixed', inset: 0, background: 'rgba(15,23,42,0.45)', zIndex: 1000,
      display: 'flex', alignItems: 'flex-start', justifyContent: 'center', padding: '48px 16px', overflowY: 'auto',
    }}>
      <div onClick={e => e.stopPropagation()} style={{
        background: '#fff', borderRadius: 18, width: '100%', maxWidth: 620,
        boxShadow: '0 20px 60px rgba(0,0,0,0.25)', overflow: 'hidden',
      }}>
        {/* 헤더 */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '18px 22px', borderBottom: '1px solid #f1f5f9' }}>
          <div style={{ fontSize: 16, fontWeight: 700, color: '#1e293b' }}>
            {deleted ? (d?.originalNickname ?? '탈퇴 유저') : (d?.nickname ?? '유저 상세')}
            {deleted && <span style={{ fontSize: 11, fontWeight: 600, marginLeft: 8, padding: '2px 8px', borderRadius: 99, background: '#f8fafc', color: '#64748b', border: '1px solid #e2e8f0' }}>탈퇴</span>}
          </div>
          <button onClick={onClose} style={{ border: 'none', background: 'transparent', cursor: 'pointer', color: '#94a3b8', padding: 4 }}><X size={18} /></button>
        </div>

        <div style={{ padding: '8px 22px 22px' }}>
          {err ? (
            <div style={{ padding: '40px 0', textAlign: 'center', color: '#dc2626', fontSize: 13 }}>{err}</div>
          ) : !d ? (
            <div style={{ padding: '40px 0', textAlign: 'center', color: '#94a3b8', fontSize: 13 }}>불러오는 중...</div>
          ) : (
            <>
              {/* 기본 정보 */}
              <div style={{ fontSize: 12, fontWeight: 700, color: '#6366f1', margin: '16px 0 4px' }}>기본 정보</div>
              <DRow label="ID">{d.id}</DRow>
              {deleted ? (
                <>
                  <DRow label="원본 이메일">{d.originalEmail}</DRow>
                  <DRow label="탈퇴일">{fmtDt(d.deletedAt)}</DRow>
                  <DRow label="완전삭제 예정">{d.purgeAfter ? String(d.purgeAfter).slice(0, 10) : '-'}</DRow>
                </>
              ) : (
                <>
                  <DRow label="이메일">{d.email}</DRow>
                  <DRow label="가입 경로">{d.provider}</DRow>
                  <DRow label="가입일">{fmtDt(d.createdAt)}</DRow>
                  <DRow label="상태">{d.suspended ? <span style={{ color: '#dc2626', fontWeight: 600 }}>정지 — {d.suspensionReason ?? ''}</span> : <span style={{ color: '#16a34a', fontWeight: 600 }}>활성</span>}</DRow>
                </>
              )}
              <DRow label="보존 활동">카드 {d.assetCount ?? 0} · 판매글 {d.tradePostCount ?? 0} · 매수 {d.buyOrderCount ?? 0} · 스캔 {scanCount}</DRow>

              {/* 등록한 카드 — 유저가 등록할 때 찍은 실제 사진(asset_images). 학습동의(scan_image_consent)와 무관하게 항상 열람. */}
              <div style={{ fontSize: 12, fontWeight: 700, color: '#6366f1', margin: '20px 0 8px' }}>
                등록한 카드 {(d.assetCount ?? 0) > 0 ? `(${d.assetCount}장)` : ''}
              </div>
              {(d.assetCount ?? 0) === 0 ? (
                <div style={{ fontSize: 12, color: '#94a3b8', padding: '6px 0' }}>등록한 카드가 없습니다.</div>
              ) : assets === null ? (
                <button onClick={loadAssets} disabled={assetLoading} style={{
                  display: 'inline-flex', alignItems: 'center', gap: 6, padding: '8px 14px', borderRadius: 9,
                  border: '1px solid #6366f1', background: '#6366f1', color: '#fff', fontSize: 13, fontWeight: 600, cursor: 'pointer',
                }}><ImageIcon size={14} /> {assetLoading ? '불러오는 중...' : `등록 카드 + 사진 보기 (${d.assetCount}장)`}</button>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {assets.map(a => (
                    <div key={a.assetId} style={{ border: '1px solid #eef1f6', borderRadius: 10, padding: '10px 12px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, marginBottom: 8 }}>
                        <div style={{ fontSize: 13, fontWeight: 600, color: '#1e293b', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                          {a.cardName ?? a.cardId}
                          {a.rarity && <span style={{ marginLeft: 6, fontSize: 10, fontWeight: 700, color: '#64748b', background: '#f1f5f9', borderRadius: 4, padding: '1px 5px' }}>{a.rarity}</span>}
                        </div>
                        <div style={{ fontSize: 11, color: '#94a3b8', whiteSpace: 'nowrap', flexShrink: 0 }}>
                          {a.gradingCompany ? `${a.gradingCompany} ${a.gradeValue ?? ''}` : 'RAW'}{a.language ? ` · ${a.language}` : ''}
                        </div>
                      </div>
                      {a.images && a.images.length > 0 ? (
                        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                          {a.images.map((img, i) => (
                            <div key={i} style={{ width: 92, border: '1px solid #eef1f6', borderRadius: 8, overflow: 'hidden', position: 'relative' }}>
                              {img.imageUrl
                                ? <img src={img.imageUrl} alt={img.imageType} onClick={() => setZoom(img.imageUrl)} style={{ width: '100%', height: 124, objectFit: 'cover', display: 'block', cursor: 'zoom-in', background: '#f8fafc' }} />
                                : <div style={{ width: '100%', height: 124, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#cbd5e1', fontSize: 10, background: '#f8fafc' }}>이미지 없음</div>}
                              <div style={{ position: 'absolute', top: 4, left: 4, fontSize: 9, fontWeight: 700, color: '#fff', background: 'rgba(15,23,42,0.6)', borderRadius: 4, padding: '1px 5px' }}>{img.imageType}</div>
                            </div>
                          ))}
                        </div>
                      ) : (
                        <div style={{ fontSize: 11, color: '#cbd5e1' }}>실촬영 사진 없음</div>
                      )}
                    </div>
                  ))}
                </div>
              )}

              {!deleted && (
                <>
                  {/* 약관 · 동의 */}
                  <div style={{ fontSize: 12, fontWeight: 700, color: '#6366f1', margin: '20px 0 4px' }}>약관 · 동의</div>
                  <DRow label="서비스 약관"><Consent ok on="가입 시 동의" /></DRow>
                  <DRow label="만 14세 확인"><Consent ok={!!d.isOver14} on="확인됨" off="미확인" at={d.ageCheckedAt} /></DRow>
                  <DRow label="휴대폰 인증"><Consent ok={!!d.phoneVerified} on="인증됨" off="미인증" at={d.phoneVerifiedAt} />{d.phoneVerified && d.phoneE164 && <span style={{ marginLeft: 8, fontSize: 12, color: '#475569' }}>{d.phoneE164}</span>}</DRow>
                  <DRow label="스캔이미지 수집"><Consent ok={!!d.scanImageConsent} at={d.scanImageConsentAt} /></DRow>

                  {/* 스캔 데이터 */}
                  <div style={{ fontSize: 12, fontWeight: 700, color: '#6366f1', margin: '20px 0 8px' }}>스캔 데이터 {scanCount > 0 && `(${scanCount}장)`}</div>
                  {!d.scanImageConsent ? (
                    <div style={{ fontSize: 12, color: '#94a3b8', padding: '6px 0' }}>스캔이미지 수집 미동의 — 사진을 보관하지 않습니다.</div>
                  ) : scanCount === 0 ? (
                    <div style={{ fontSize: 12, color: '#94a3b8', padding: '6px 0' }}>저장된 스캔 캡처가 없습니다.</div>
                  ) : scans === null ? (
                    <button onClick={loadScans} disabled={scanLoading} style={{
                      display: 'inline-flex', alignItems: 'center', gap: 6, padding: '8px 14px', borderRadius: 9,
                      border: '1px solid #6366f1', background: '#6366f1', color: '#fff', fontSize: 13, fontWeight: 600, cursor: 'pointer',
                    }}><ImageIcon size={14} /> {scanLoading ? '불러오는 중...' : `스캔 사진 보기 (${scanCount}장)`}</button>
                  ) : (
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 10 }}>
                      {scans.map(s => (
                        <div key={s.captureId} style={{ border: '1px solid #eef1f6', borderRadius: 10, overflow: 'hidden' }}>
                          {s.imageUrl
                            ? <img src={s.imageUrl} alt={s.cardName ?? ''} onClick={() => setZoom(s.imageUrl)} style={{ width: '100%', height: 130, objectFit: 'cover', display: 'block', cursor: 'zoom-in', background: '#f8fafc' }} />
                            : <div style={{ width: '100%', height: 130, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#cbd5e1', fontSize: 11, background: '#f8fafc' }}>이미지 없음</div>}
                          <div style={{ padding: '6px 8px' }}>
                            <div style={{ fontSize: 11, fontWeight: 600, color: '#1e293b', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{s.cardName ?? s.cardId}</div>
                            <div style={{ fontSize: 10, color: '#94a3b8', marginTop: 2 }}>
                              {s.matchConfidence != null ? `신뢰 ${(s.matchConfidence * 100).toFixed(0)}%` : ''} · {s.createdAt ? String(s.createdAt).slice(5, 10) : ''}
                            </div>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </>
              )}
            </>
          )}
        </div>
      </div>

      {/* 이미지 확대 */}
      {zoom && (
        <div onClick={(e) => { e.stopPropagation(); setZoom(null) }} style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.8)', zIndex: 1100,
          display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24, cursor: 'zoom-out',
        }}>
          <img src={zoom} alt="" style={{ maxWidth: '90%', maxHeight: '90%', borderRadius: 8 }} />
        </div>
      )}
    </div>
  )
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
  const [tab, setTab] = useState('active') // active | deleted
  const [modalUserId, setModalUserId] = useState(null)
  const size = 15

  const reload = () =>
    api.get('/admin/users', { params: { page, size, search: search || undefined } })
      .then(r => {
        setUsers(r.data?.data?.content ?? [])
        setTotal(r.data?.data?.totalElements ?? 0)
      })

  useEffect(() => {
    setLoading(true)
    reload().catch(() => { setUsers([]); setTotal(0) }).finally(() => setLoading(false))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, search])

  const totalPages = Math.ceil(total / size)
  const isDel = u => u.deleted === true || !!u.deletedAt
  const shown = users.filter(u => (tab === 'deleted' ? isDel(u) : !isDel(u)))

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

      {/* 활성 / 탈퇴 탭 */}
      <div style={{ display: 'flex', gap: 6, marginBottom: 14 }}>
        {[['active', '활성'], ['deleted', '탈퇴']].map(([k, label]) => (
          <button key={k} onClick={() => setTab(k)} style={{
            padding: '6px 16px', borderRadius: 8, fontSize: 13, fontWeight: 600, cursor: 'pointer',
            border: '1px solid ' + (tab === k ? '#6366f1' : '#e2e8f0'),
            background: tab === k ? '#6366f1' : '#fff',
            color: tab === k ? '#fff' : '#64748b',
          }}>{label}</button>
        ))}
      </div>

      <div style={S.card}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              {['ID', '닉네임', '이메일', '가입일', '카드', '거래', '상태', '액션'].map(h => (
                <th key={h} style={S.th}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={8} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>불러오는 중...</td></tr>
            ) : shown.length === 0 ? (
              <tr><td colSpan={8} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '40px' }}>{tab === 'deleted' ? '탈퇴한 유저가 없습니다' : '유저가 없습니다'}</td></tr>
            ) : shown.map(u => {
              // 백엔드 응답: suspended (boolean) / status (legacy). suspended true 면 정지 상태.
              const isSuspended = u.suspended === true || u.status === 'BANNED'
              const isDeleted = u.deleted === true || u.deletedAt
              return (
              <tr key={u.id || u.userId} style={{ transition: 'background 0.1s' }}
                onMouseEnter={e => e.currentTarget.style.background = '#fafafa'}
                onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
              >
                <td style={{ ...S.td, fontSize: 12 }}>
                  <button onClick={() => setModalUserId(u.id || u.userId)} style={{ border: 'none', background: 'transparent', color: '#6366f1', fontSize: 12, fontWeight: 600, cursor: 'pointer', padding: 0, fontFamily: 'inherit' }}>{u.id || u.userId}</button>
                </td>
                <td style={{ ...S.td, fontWeight: 600 }}>
                  <button onClick={() => setModalUserId(u.id || u.userId)} style={{ border: 'none', background: 'transparent', color: '#1e293b', fontSize: 13, fontWeight: 600, cursor: 'pointer', padding: 0, fontFamily: 'inherit' }}>{u.nickname ?? '-'}</button>
                </td>
                <td style={S.td}>{u.email ?? '-'}</td>
                <td style={{ ...S.td, fontSize: 12 }}>{u.createdAt ? u.createdAt.slice(0, 10) : '-'}</td>
                <td style={S.td}>{(u.cardCount ?? 0).toLocaleString()}</td>
                <td style={S.td}>{(u.tradeCount ?? 0).toLocaleString()}</td>
                <td style={S.td}><Badge status={isDeleted ? 'INACTIVE' : (isSuspended ? 'BANNED' : 'ACTIVE')} /></td>
                <td style={S.td}>
                  {isDeleted ? (
                    <button onClick={() => setModalUserId(u.id || u.userId)} style={{
                      padding: '4px 10px', borderRadius: 6, background: '#fff',
                      border: '1px solid #6366f1', color: '#6366f1',
                      fontSize: 11, fontWeight: 600, cursor: 'pointer',
                    }}>원본 보기</button>
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
                    <div style={{ display: 'inline-flex', gap: 6 }}>
                      <button onClick={async () => {
                        const ok = await warnUser(u.id || u.userId)
                        if (ok) api.get('/admin/users', { params: { page, size, search: search || undefined } }).then(r => { setUsers(r.data?.data?.content ?? []); setTotal(r.data?.data?.totalElements ?? 0) })
                      }} style={{
                        display: 'inline-flex', alignItems: 'center', gap: 4,
                        padding: '4px 10px', borderRadius: 6,
                        background: '#fff', border: '1px solid #d97706',
                        color: '#d97706', fontSize: 11, fontWeight: 600, cursor: 'pointer',
                      }}><AlertTriangle size={12} /> 경고</button>
                      <button onClick={async () => {
                        const ok = await suspendUser(u.id || u.userId)
                        if (ok) api.get('/admin/users', { params: { page, size, search: search || undefined } }).then(r => { setUsers(r.data?.data?.content ?? []); setTotal(r.data?.data?.totalElements ?? 0) })
                      }} style={{
                        display: 'inline-flex', alignItems: 'center', gap: 4,
                        padding: '4px 10px', borderRadius: 6,
                        background: '#fff', border: '1px solid #dc2626',
                        color: '#dc2626', fontSize: 11, fontWeight: 600, cursor: 'pointer',
                      }}><Ban size={12} /> 정지</button>
                      <button onClick={async () => {
                        const ok = await deleteUserAdmin(u.id || u.userId)
                        if (ok) reload()
                      }} style={{
                        padding: '4px 10px', borderRadius: 6, background: '#fff',
                        border: '1px solid #475569', color: '#475569',
                        fontSize: 11, fontWeight: 600, cursor: 'pointer',
                      }}>탈퇴 처리</button>
                    </div>
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

      {modalUserId && <UserDetailModal userId={modalUserId} onClose={() => setModalUserId(null)} />}
    </div>
  )
}
