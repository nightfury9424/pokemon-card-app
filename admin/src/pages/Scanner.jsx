import { useEffect, useRef, useState } from 'react'
import { RefreshCw, Database, Cpu, Clock, Search, CheckCircle, XCircle, Play, UploadCloud, Hourglass } from 'lucide-react'
import api from '../api'

const STATUS_KO = {
  NONE: '대기', REQUESTED: '학습 요청됨(맥 agent 대기)', TRAINING: '학습 중',
  TRAINED: '학습 완료 — 배포 대기', DEPLOYING: '배포 중', DEPLOYED: '배포 완료', FAILED: '실패',
}
function fmtDur(s) {
  if (s == null) return '—'
  const m = Math.floor(s / 60), r = s % 60
  return m > 0 ? `${m}분 ${r}초` : `${r}초`
}

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
  const [testImg, setTestImg]   = useState('')
  const [testResult, setTestResult] = useState(null)
  const [testing, setTesting]   = useState(false)
  const [train, setTrain]       = useState(null)   // train-status 응답
  const [busy, setBusy]         = useState(false)
  const pollRef = useRef(null)

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

  function loadTrain() {
    return api.get('/admin/scanner/train-status')
      .then(r => setTrain(r.data ?? null))
      .catch(() => setTrain(null))
  }

  useEffect(() => { loadInfo(); loadScans(); loadTrain() }, [])

  // 진행 중(REQUESTED/TRAINING/DEPLOYING)이면 3초 폴링 — 경과시간/완료 자동 반영.
  useEffect(() => {
    const active = ['REQUESTED', 'TRAINING', 'DEPLOYING'].includes(train?.status)
    clearInterval(pollRef.current)
    if (active) pollRef.current = setInterval(loadTrain, 3000)
    return () => clearInterval(pollRef.current)
  }, [train?.status])

  function doTrain() {
    if (busy || !train?.canTrain) return
    setBusy(true)
    api.post('/admin/scanner/train')
      .then(() => loadTrain())
      .catch(e => alert('학습 요청 실패: ' + (e.response?.data?.message ?? e.message)))
      .finally(() => setBusy(false))
  }

  function doDeploy() {
    if (busy || !train?.canDeploy) return
    if (!window.confirm('학습된 인덱스를 운영 스캐너에 무중단 배포합니다. 진행할까요?')) return
    setBusy(true)
    api.post('/admin/scanner/deploy')
      .then(r => { alert('배포 완료 — 반영 ' + (r.data?.markedIndexed ?? 0) + '개'); loadTrain() })
      .catch(e => alert('배포 실패: ' + (e.response?.data?.message ?? e.message)))
      .finally(() => setBusy(false))
  }

  function doReset() {
    if (busy) return
    if (!window.confirm('진행 중 job 을 강제 종료합니다(배포 중 멈춤 복구용). 진행할까요?')) return
    setBusy(true)
    api.post('/admin/scanner/reset')
      .then(() => loadTrain())
      .catch(e => alert('리셋 실패: ' + (e.response?.data?.message ?? e.message)))
      .finally(() => setBusy(false))
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
        <button onClick={() => { loadInfo(); loadScans(); loadTrain() }} style={{
          display: 'flex', alignItems: 'center', gap: 6,
          padding: '9px 16px', borderRadius: 10, border: '1px solid #e2e8f0', cursor: 'pointer',
          background: '#fff', color: '#475569', fontSize: 13, fontWeight: 600, fontFamily: 'inherit',
        }}>
          <RefreshCw size={13} /> 새로고침
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

      {/* 모델 재학습 — 맥북 agent 오케스트레이션. 학습은 맥에서(서버비용 0), 완료 후 무중단 배포. */}
      <div style={{ ...S.card, padding: '24px', marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
          <Cpu size={15} color="#6366f1" />
          <div style={{ fontSize: 15, fontWeight: 700, color: '#1e293b' }}>모델 재학습</div>
        </div>
        <div style={{ fontSize: 12, color: '#94a3b8', marginBottom: 18 }}>
          유저 스캔 캡처로 FAISS 인덱스 보강 — 학습은 맥북 agent 에서, 완료 후 운영에 무중단 반영
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 28, flexWrap: 'wrap', marginBottom: 18 }}>
          <div>
            <div style={{ fontSize: 11, color: '#94a3b8', fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 4 }}>새 데이터 (미반영 캡처)</div>
            <div style={{ fontSize: 26, fontWeight: 800, color: (train?.unindexedCaptures > 0) ? '#6366f1' : '#1e293b', letterSpacing: -0.5 }}>
              {(train?.unindexedCaptures ?? 0).toLocaleString()}개
            </div>
          </div>
          <div>
            <div style={{ fontSize: 11, color: '#94a3b8', fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 4 }}>상태</div>
            <div style={{ fontSize: 15, fontWeight: 700, color: train?.status === 'FAILED' ? '#dc2626' : '#1e293b' }}>
              {STATUS_KO[train?.status] ?? train?.status ?? '—'}
            </div>
          </div>
          {train?.status === 'TRAINING' && (
            <div>
              <div style={{ fontSize: 11, color: '#94a3b8', fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 4 }}>경과</div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 15, fontWeight: 700, color: '#f59e0b' }}>
                <Hourglass size={13} /> {fmtDur(train?.elapsedSeconds)}
              </div>
            </div>
          )}
          {train?.lastTrainSeconds != null && (
            <div>
              <div style={{ fontSize: 11, color: '#94a3b8', fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 4 }}>지난번 소요(참고)</div>
              <div style={{ fontSize: 15, fontWeight: 700, color: '#64748b' }}>~{fmtDur(train?.lastTrainSeconds)}</div>
            </div>
          )}
        </div>

        {train?.status === 'FAILED' && train?.message && (
          <div style={{ fontSize: 12, color: '#dc2626', background: '#fef2f2', border: '1px solid #fecaca', borderRadius: 10, padding: '10px 12px', marginBottom: 14 }}>
            {train.message}
          </div>
        )}

        <div style={{ display: 'flex', gap: 10 }}>
          <button onClick={doTrain} disabled={busy || !train?.canTrain} style={{
            display: 'flex', alignItems: 'center', gap: 6, padding: '10px 18px', borderRadius: 10, border: 'none',
            cursor: (busy || !train?.canTrain) ? 'not-allowed' : 'pointer',
            background: (busy || !train?.canTrain) ? '#cbd5e1' : 'linear-gradient(135deg, #6366f1, #4f46e5)',
            color: '#fff', fontSize: 13, fontWeight: 600, fontFamily: 'inherit',
          }}>
            <Play size={13} /> 학습하기
          </button>
          <button onClick={doDeploy} disabled={busy || !train?.canDeploy} style={{
            display: 'flex', alignItems: 'center', gap: 6, padding: '10px 18px', borderRadius: 10,
            border: train?.canDeploy ? 'none' : '1px solid #e2e8f0',
            cursor: (busy || !train?.canDeploy) ? 'not-allowed' : 'pointer',
            background: (busy || !train?.canDeploy) ? '#f1f5f9' : 'linear-gradient(135deg, #16a34a, #15803d)',
            color: (busy || !train?.canDeploy) ? '#94a3b8' : '#fff', fontSize: 13, fontWeight: 600, fontFamily: 'inherit',
          }}>
            <UploadCloud size={13} /> 업데이트하기
          </button>
          {train && !train.canTrain && train.status !== 'NONE' && (
            <button onClick={doReset} disabled={busy} style={{
              padding: '10px 14px', borderRadius: 10, border: '1px solid #fecaca',
              cursor: busy ? 'not-allowed' : 'pointer', background: '#fff', color: '#dc2626',
              fontSize: 12, fontWeight: 600, fontFamily: 'inherit',
            }}>
              강제 종료
            </button>
          )}
          <div style={{ flex: 1 }} />
          <div style={{ fontSize: 11, color: '#cbd5e1', alignSelf: 'center', textAlign: 'right', maxWidth: 220 }}>
            학습하기 → 맥에서 <code>train_agent.py</code> 실행 → 완료되면 업데이트하기 활성
          </div>
        </div>
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
