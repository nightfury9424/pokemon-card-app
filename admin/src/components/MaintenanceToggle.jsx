import { useEffect, useState } from 'react'
import { AlertTriangle, Power, ShieldCheck } from 'lucide-react'
import api from '../api'

// 2026-06-12 점검(maintenance) ON/OFF — app-config/maintenance.json(S3, card CDN) 토글.
// 켜면 전 버전 앱 사용자가 점검화면으로 전환(최대 ~1분 지연). 긴급 백서버 점검용.
export default function MaintenanceToggle() {
  const [state, setState] = useState(null) // { maintenance, message }
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)

  const load = () =>
    api.get('/admin/maintenance')
      .then(r => { const d = r.data?.data ?? {}; setState(d); setMsg(d.message ?? '') })
      .catch(() => setState({ maintenance: false, message: '' }))

  useEffect(() => { load() }, [])

  const toggle = async (on) => {
    if (on && !window.confirm('점검 모드를 켤까요?\n전 버전 앱 사용자가 점검 화면으로 전환됩니다 (반영까지 최대 1분).')) return
    if (!on && !window.confirm('점검을 해제할까요?')) return
    setBusy(true)
    try {
      const r = await api.post('/admin/maintenance', { maintenance: on, message: msg })
      const d = r.data?.data ?? null
      if (d) { setState(d); setMsg(d.message ?? '') }
    } catch (e) {
      alert(e.response?.data?.message ?? '처리 실패')
    } finally { setBusy(false) }
  }

  const on = state?.maintenance === true
  const loading = state === null

  return (
    <div style={{
      marginBottom: 16, borderRadius: 14, overflow: 'hidden',
      border: `1px solid ${on ? '#fecaca' : '#e8edf4'}`,
      background: on ? '#fff5f5' : '#fff',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '14px 20px', gap: 16, flexWrap: 'wrap' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          {on ? <AlertTriangle size={18} color="#dc2626" /> : <ShieldCheck size={18} color="#16a34a" />}
          <div>
            <div style={{ fontSize: 14, fontWeight: 700, color: on ? '#b91c1c' : '#1e293b' }}>
              점검 모드 {loading ? '확인 중…' : on ? 'ON — 앱 차단 중' : 'OFF — 정상 운영'}
            </div>
            <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 2 }}>
              켜면 전 버전 앱 사용자에게 점검 화면 표시 (반영 최대 ~1분)
            </div>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <input
            value={msg}
            onChange={e => setMsg(e.target.value)}
            placeholder="점검 안내 문구 (비우면 기본 문구)"
            style={{
              width: 280, padding: '8px 12px', borderRadius: 9, border: '1px solid #e2e8f0',
              fontSize: 12, color: '#1e293b', outline: 'none', fontFamily: 'inherit',
            }}
          />
          {on ? (
            <button onClick={() => toggle(false)} disabled={busy || loading} style={{
              display: 'inline-flex', alignItems: 'center', gap: 6, padding: '8px 16px', borderRadius: 9,
              border: '1px solid #16a34a', background: '#16a34a', color: '#fff',
              fontSize: 13, fontWeight: 600, cursor: busy ? 'wait' : 'pointer', opacity: busy ? 0.6 : 1, whiteSpace: 'nowrap',
            }}><ShieldCheck size={14} /> {busy ? '처리 중…' : '점검 해제'}</button>
          ) : (
            <button onClick={() => toggle(true)} disabled={busy || loading} style={{
              display: 'inline-flex', alignItems: 'center', gap: 6, padding: '8px 16px', borderRadius: 9,
              border: '1px solid #dc2626', background: '#dc2626', color: '#fff',
              fontSize: 13, fontWeight: 600, cursor: busy ? 'wait' : 'pointer', opacity: busy ? 0.6 : 1, whiteSpace: 'nowrap',
            }}><Power size={14} /> {busy ? '처리 중…' : '점검 시작'}</button>
          )}
        </div>
      </div>
    </div>
  )
}
