import { useEffect, useState } from 'react'
import { RefreshCw, Database, Cpu, Clock, Search, CheckCircle, XCircle } from 'lucide-react'
import api from '../api'

const S = {
  page:  { padding: '32px 36px', minHeight: '100%', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' },
  h1:    { fontSize: 22, fontWeight: 700, color: '#1e293b', letterSpacing: -0.5, marginBottom: 4 },
  sub:   { fontSize: 13, color: '#94a3b8', marginBottom: 28 },
  card:  { background: '#fff', borderRadius: 16, border: '1px solid #e8edf4', boxShadow: '0 1px 3px rgba(0,0,0,0.04)' },
  grid3: { display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16, marginBottom: 16 },
  th:    { padding: '12px 16px', fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.6, textAlign: 'left', background: '#f8fafc', borderBottom: '1px solid #f1f5f9' },
  td:    { padding: '12px 16px', fontSize: 13, color: '#475569', borderBottom: '1px solid #f8fafc' },
}

function InfoCard({ icon: Icon, label, value, color }) {
  return (
    <div style={{ ...S.card, padding: '20px 24px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 14 }}>
        <div style={{ width: 36, height: 36, borderRadius: 10, background: color + '18', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon size={16} color={color} />
        </div>
        <span style={{ fontSize: 13, color: '#64748b', fontWeight: 500 }}>{label}</span>
      </div>
      <div style={{ fontSize: 26, fontWeight: 800, color: '#1e293b', letterSpacing: -0.5 }}>{value ?? '—'}</div>
    </div>
  )
}

export default function Scanner() {
  const [info, setInfo]         = useState(null)
  const [scans, setScans]       = useState([])
  const [rebuilding, setRebuilding] = useState(false)
  const [testImg, setTestImg]   = useState('')
  const [testResult, setTestResult] = useState(null)
  const [testing, setTesting]   = useState(false)

  // 2026-05-29 P-1: localhost:8082 직접 호출 → backend proxy 사용 (브라우저에서 prod scanner 미도달 문제 해결).
  //   - /admin/scanner/stats : backend 가 docker network 안 scanner:8082/health → vectors 카운트 반환.
  //   - /rebuild, /scan 은 scanner 측 미구현 (404) → 버튼 disable + 안내 메시지.
  function loadInfo() {
    api.get('/admin/scanner/stats')
      .then(r => setInfo(r.data?.data ?? null))
      .catch(() => setInfo({ connected: false }))
  }

  function loadScans() {
    api.get('/admin/stats/scans/recent')
      .then(r => setScans(r.data?.data ?? []))
      .catch(() => setScans([]))
  }

  useEffect(() => { loadInfo(); loadScans() }, [])

  function rebuild() {
    alert('FAISS 재빌드는 현재 운영 스캐너에 미구현 — 별도 작업으로 분리됨')
  }

  function testScan() {
    if (!testImg.trim()) return
    alert('스캔 테스트는 현재 운영 스캐너에 /scan endpoint 미연동 — 별도 작업으로 분리됨')
    setTestResult({ ok: false, msg: '운영 스캐너 /scan endpoint 미연동' })
  }

  return (
    <div style={S.page}>
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 4 }}>
        <div style={S.h1}>스캐너</div>
        <button onClick={rebuild} disabled={rebuilding} style={{
          display: 'flex', alignItems: 'center', gap: 6,
          padding: '9px 16px', borderRadius: 10, border: 'none', cursor: rebuilding ? 'not-allowed' : 'pointer',
          background: rebuilding ? '#cbd5e1' : 'linear-gradient(135deg, #6366f1, #4f46e5)',
          color: '#fff', fontSize: 13, fontWeight: 600, fontFamily: 'inherit',
        }}>
          <RefreshCw size={13} style={{ animation: rebuilding ? 'spin 1s linear infinite' : 'none' }} />
          {rebuilding ? '재빌드 중...' : 'FAISS 재빌드'}
        </button>
      </div>
      <div style={S.sub}>DINOv2 + FAISS 스캐너 현황</div>

      {/* 스탯 카드 3개 — 2026-05-29 P-1: backend proxy 응답 필드 (connected/totalVectors/dim/...) 사용.
          미연동 시 "—" 대신 "연동 안 됨" 명시. */}
      <div style={S.grid3}>
        <InfoCard icon={Database} label="인덱스 벡터 수"    color="#6366f1"
          value={info?.connected ? Number(info.totalVectors ?? 0).toLocaleString() : '연동 안 됨'} />
        <InfoCard icon={Cpu}      label="임베딩 차원"       color="#06b6d4"
          value={info?.connected ? (info.dim ?? 1536) : '연동 안 됨'} />
        <InfoCard icon={Clock}    label="마지막 업데이트"   color="#f59e0b"
          value={info?.connected ? (info.lastUpdated ? String(info.lastUpdated).slice(0, 10) : 'N/A') : '연동 안 됨'} />
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>

        {/* 테스트 스캔 */}
        <div style={{ ...S.card, padding: '24px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16 }}>
            <Search size={15} color="#6366f1" />
            <div style={{ fontSize: 15, fontWeight: 700, color: '#1e293b' }}>스캔 테스트</div>
          </div>

          <div style={{ marginBottom: 12 }}>
            <div style={{ fontSize: 12, fontWeight: 600, color: '#64748b', textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 8 }}>이미지 URL</div>
            <div style={{ display: 'flex', gap: 8 }}>
              <input
                value={testImg}
                onChange={e => setTestImg(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && testScan()}
                placeholder="https://... 또는 카드 이미지 URL"
                style={{
                  flex: 1, padding: '10px 14px', borderRadius: 10,
                  border: '1px solid #e2e8f0', fontSize: 13, color: '#1e293b',
                  outline: 'none', fontFamily: 'inherit', background: '#f8fafc',
                }}
              />
              <button onClick={testScan} disabled={testing} style={{
                padding: '10px 16px', borderRadius: 10, border: 'none', cursor: testing ? 'not-allowed' : 'pointer',
                background: 'linear-gradient(135deg, #6366f1, #4f46e5)',
                color: '#fff', fontSize: 13, fontWeight: 600, fontFamily: 'inherit', flexShrink: 0,
              }}>
                {testing ? <RefreshCw size={13} style={{ animation: 'spin 1s linear infinite' }} /> : '스캔'}
              </button>
            </div>
          </div>

          {testResult && (
            <div style={{ borderRadius: 12, padding: '14px', background: testResult.ok ? '#f0fdf4' : '#fef2f2', border: `1px solid ${testResult.ok ? '#bbf7d0' : '#fecaca'}` }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: testResult.ok ? 10 : 0 }}>
                {testResult.ok ? <CheckCircle size={14} color="#16a34a" /> : <XCircle size={14} color="#dc2626" />}
                <span style={{ fontSize: 13, fontWeight: 600, color: testResult.ok ? '#16a34a' : '#dc2626' }}>
                  {testResult.ok ? '스캔 성공' : testResult.msg}
                </span>
              </div>
              {testResult.ok && testResult.data?.results?.slice(0, 3).map((r, i) => (
                <div key={i} style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0', borderBottom: i < 2 ? '1px solid #dcfce7' : 'none' }}>
                  <span style={{ fontSize: 13, color: '#1e293b', fontWeight: i === 0 ? 700 : 400 }}>{r.card_id}</span>
                  <span style={{ fontSize: 12, color: '#16a34a' }}>{(r.similarity * 100).toFixed(1)}%</span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* 최근 스캔 */}
        <div style={{ ...S.card, overflow: 'hidden' }}>
          <div style={{ padding: '20px 24px 12px', fontSize: 15, fontWeight: 700, color: '#1e293b' }}>최근 스캔</div>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr>
                {['유저', '결과 카드', '유사도', '시각'].map(h => (
                  <th key={h} style={S.th}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {scans.length === 0 ? (
                <tr><td colSpan={4} style={{ ...S.td, textAlign: 'center', color: '#94a3b8', padding: '32px' }}>스캔 기록이 없습니다</td></tr>
              ) : scans.map((s, i) => (
                <tr key={i}
                  onMouseEnter={e => e.currentTarget.style.background = '#fafafa'}
                  onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
                >
                  <td style={S.td}>{s.userNickname ?? '-'}</td>
                  <td style={{ ...S.td, fontWeight: 600, color: '#1e293b' }}>{s.resultCardId ?? '-'}</td>
                  <td style={{ ...S.td, color: '#6366f1', fontWeight: 600 }}>
                    {s.similarity != null ? `${(s.similarity * 100).toFixed(1)}%` : '-'}
                  </td>
                  <td style={{ ...S.td, fontSize: 12, color: '#94a3b8' }}>
                    {s.createdAt ? s.createdAt.slice(11, 16) : '-'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
