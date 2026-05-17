import { useEffect, useState, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { Users, CreditCard, ScanLine, ArrowLeftRight, RefreshCw, TrendingUp, TrendingDown, AlertTriangle, ExternalLink } from 'lucide-react'
import {
  AreaChart, Area, BarChart, Bar,
  XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, Legend,
} from 'recharts'
import api from '../api'

/* ── 공통 스타일 ── */
const S = {
  page:  { padding: '28px 32px', minHeight: '100%', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' },
  card:  { background: '#fff', borderRadius: 16, border: '1px solid #e8edf4', boxShadow: '0 1px 4px rgba(0,0,0,0.05)' },
  label: { fontSize: 11, fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.6 },
  h2:    { fontSize: 14, fontWeight: 700, color: '#1e293b', marginBottom: 16 },
}

/* ── 커스텀 툴팁 ── */
function ChartTooltip({ active, payload, label, unit = '' }) {
  if (!active || !payload?.length) return null
  return (
    <div style={{ background: '#1e293b', borderRadius: 10, padding: '10px 14px', boxShadow: '0 8px 24px rgba(0,0,0,0.2)' }}>
      <div style={{ color: '#94a3b8', fontSize: 11, marginBottom: 6 }}>{label}</div>
      {payload.map(p => (
        <div key={p.name} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13 }}>
          <span style={{ width: 8, height: 8, borderRadius: '50%', background: p.color, display: 'inline-block' }} />
          <span style={{ color: '#cbd5e1' }}>{p.name}</span>
          <span style={{ color: '#fff', fontWeight: 700, marginLeft: 4 }}>{p.value.toLocaleString()}{unit}</span>
        </div>
      ))}
    </div>
  )
}

/* ── 스탯 카드 ── */
function StatCard({ icon: Icon, label, value, sub, delta, color }) {
  const palette = {
    indigo: '#6366f1', cyan: '#06b6d4', emerald: '#10b981', amber: '#f59e0b',
  }
  const c = palette[color] ?? palette.indigo
  const isUp = delta >= 0

  return (
    <div style={{ ...S.card, padding: '20px 22px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 14 }}>
        <div style={{ width: 38, height: 38, borderRadius: 10, background: c + '18', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon size={17} color={c} strokeWidth={2} />
        </div>
        {delta !== undefined && (
          <div style={{
            display: 'flex', alignItems: 'center', gap: 3,
            fontSize: 11, fontWeight: 700, padding: '3px 7px', borderRadius: 99,
            background: isUp ? '#f0fdf4' : '#fef2f2',
            color: isUp ? '#16a34a' : '#dc2626',
          }}>
            {isUp ? <TrendingUp size={10} /> : <TrendingDown size={10} />}
            {Math.abs(delta)}%
          </div>
        )}
      </div>
      <div style={{ fontSize: 28, fontWeight: 800, color: '#1e293b', letterSpacing: -1, lineHeight: 1 }}>
        {value ?? <span style={{ color: '#e2e8f0' }}>—</span>}
      </div>
      <div style={{ fontSize: 12, color: '#64748b', marginTop: 6, fontWeight: 500 }}>{label}</div>
      {sub && <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 3 }}>{sub}</div>}
    </div>
  )
}

/* ── 서비스 상태 ── */
function ServiceDot({ status }) {
  const color = status === 'ok' ? '#22c55e' : status === 'error' ? '#ef4444' : '#f59e0b'
  const glow  = status === 'ok' ? 'rgba(34,197,94,0.5)' : status === 'error' ? 'rgba(239,68,68,0.5)' : 'rgba(245,158,11,0.5)'
  return (
    <span style={{
      width: 8, height: 8, borderRadius: '50%', background: color,
      boxShadow: `0 0 6px ${glow}`,
      display: 'inline-block',
      animation: status === 'checking' ? 'pulse 1.5s infinite' : 'none',
    }} />
  )
}

function ServiceRow({ name, url }) {
  const [st, setSt] = useState('checking')
  const [ms, setMs] = useState(null)
  useEffect(() => {
    const t = Date.now()
    api.get(url)
      .then(() => { setSt('ok'); setMs(Date.now() - t) })
      .catch(() => setSt('error'))
  }, [url])
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '11px 0', borderBottom: '1px solid #f8fafc' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <ServiceDot status={st} />
        <span style={{ fontSize: 13, color: '#475569', fontWeight: 500 }}>{name}</span>
      </div>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
        <span style={{ fontSize: 12, fontWeight: 600, color: st === 'ok' ? '#16a34a' : st === 'error' ? '#dc2626' : '#d97706' }}>
          {st === 'ok' ? 'Running' : st === 'error' ? 'Down' : 'Checking'}
        </span>
        {ms && <span style={{ fontSize: 11, color: '#cbd5e1' }}>{ms}ms</span>}
      </div>
    </div>
  )
}

const ANOMALY_LABELS = {
  CONTAMINATION_CONFIRMED: { label: '오염 데이터', color: '#dc2626', bg: '#fef2f2' },
  NO_COL_NUM:              { label: '번호 없음',   color: '#94a3b8', bg: '#f8fafc' },
  EBAY_ERROR:              { label: 'eBay 오류',  color: '#d97706', bg: '#fffbeb' },
  SKIPPED:                 { label: 'eBay 미검증', color: '#7c3aed', bg: '#fdf4ff' },
}

/* ── 메인 ── */
export default function Dashboard() {
  const navigate = useNavigate()
  const [stats,     setStats]     = useState(null)
  const [chartData, setChartData] = useState([])
  const [scanChart, setScanChart] = useState([])
  const [spinning,  setSpinning]  = useState(false)
  const [alerts,    setAlerts]    = useState([])   // 미처리 이상 알림

  const load = useCallback(() => {
    setSpinning(true)

    // 미처리 이상 알림 (최대 10건)
    api.get('/admin/price-anomalies', { params: { resolved: false, page: 0, size: 10 } })
      .then(r => setAlerts(r.data?.data?.content ?? []))
      .catch(() => {})

    /* 스탯 카드 */
    Promise.allSettled([
      api.get('/admin/stats/users'),
      api.get('/admin/stats/scans'),
      api.get('/admin/stats/trades'),
      api.get('/admin/stats/cards'),
    ]).then(([u, sc, tr, ca]) => {
      setStats({
        totalUsers:   u.value?.data?.data?.total   ?? 0,
        todayUsers:   u.value?.data?.data?.today   ?? 0,
        totalScans:   sc.value?.data?.data?.total  ?? 0,
        todayScans:   sc.value?.data?.data?.today  ?? 0,
        activeTrades: tr.value?.data?.data?.active ?? 0,
        totalCards:   ca.value?.data?.data?.total  ?? 0,
        weeklyUserDelta: u.value?.data?.data?.weeklyDelta ?? null,
        weeklyScanDelta: sc.value?.data?.data?.weeklyDelta ?? null,
      })
    })

    /* 유저 추이 차트 (최근 7일) */
    api.get('/admin/stats/users/chart')
      .then(r => setChartData(r.data?.data ?? []))
      .catch(() => {
        /* 백엔드 없을 때 더미 (0으로) */
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        setChartData(days.map(d => ({ day: d, 신규유저: 0, 누적: 0 })))
      })

    /* 스캔 추이 차트 (최근 7일) */
    api.get('/admin/stats/scans/chart')
      .then(r => setScanChart(r.data?.data ?? []))
      .catch(() => {
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        setScanChart(days.map(d => ({ day: d, 스캔수: 0 })))
      })
      .finally(() => setSpinning(false))
  }, [])

  useEffect(() => { load() }, [load])

  return (
    <div style={S.page}>

      {/* ── 헤더 ── */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 22 }}>
        <div>
          <div style={{ fontSize: 22, fontWeight: 700, color: '#1e293b', letterSpacing: -0.5 }}>대시보드</div>
          <div style={{ fontSize: 13, color: '#94a3b8', marginTop: 3 }}>포켓폴리오 운영 현황 · 실시간</div>
        </div>
        <button
          onClick={load}
          style={{
            display: 'flex', alignItems: 'center', gap: 6,
            padding: '8px 16px', borderRadius: 10, border: '1px solid #e2e8f0',
            background: '#fff', color: '#64748b', fontSize: 13, cursor: 'pointer', fontFamily: 'inherit',
          }}
        >
          <RefreshCw size={13} style={{ animation: spinning ? 'spin 1s linear infinite' : 'none' }} />
          새로고침
        </button>
      </div>

      {/* ── 가격 이상 알림 배너 ── */}
      {alerts.length > 0 && (
        <div style={{
          marginBottom: 16, borderRadius: 14,
          border: '1px solid #fecaca', background: '#fff5f5', overflow: 'hidden',
        }}>
          {/* 헤더 */}
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '14px 20px', borderBottom: '1px solid #fecaca',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <AlertTriangle size={16} color="#dc2626" />
              <span style={{ fontSize: 14, fontWeight: 700, color: '#b91c1c' }}>
                가격 이상 알림 — 검토 필요 {alerts.length}건
              </span>
              <span style={{ fontSize: 11, color: '#94a3b8' }}>
                (eBay 미검증 · 오염 확인 등 관리자 확인이 필요한 항목)
              </span>
            </div>
            <button
              onClick={() => navigate('/alerts')}
              style={{
                display: 'flex', alignItems: 'center', gap: 5,
                padding: '7px 14px', borderRadius: 8, border: 'none', cursor: 'pointer',
                background: '#dc2626', color: '#fff', fontSize: 12, fontWeight: 700, fontFamily: 'inherit',
              }}
            >
              전체 보기 <ExternalLink size={11} />
            </button>
          </div>

          {/* 항목 목록 */}
          <div style={{ padding: '8px 12px' }}>
            {alerts.map(a => {
              const meta = ANOMALY_LABELS[a.ebayResult] ?? { label: a.ebayResult ?? '-', color: '#64748b', bg: '#f8fafc' }
              return (
                <div
                  key={a.anomalyId}
                  onClick={() => navigate('/alerts')}
                  style={{
                    display: 'flex', alignItems: 'center', gap: 12,
                    padding: '9px 10px', borderRadius: 8, cursor: 'pointer',
                    transition: 'background 0.12s',
                  }}
                  onMouseEnter={e => e.currentTarget.style.background = '#fee2e2'}
                  onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
                >
                  {/* eBay 결과 뱃지 */}
                  <span style={{
                    fontSize: 10, fontWeight: 700, padding: '2px 7px', borderRadius: 99,
                    background: meta.bg, color: meta.color, border: `1px solid ${meta.color}40`,
                    whiteSpace: 'nowrap', flexShrink: 0,
                  }}>{meta.label}</span>

                  {/* 카드명 */}
                  <span style={{ fontSize: 13, fontWeight: 600, color: '#1e293b', flex: '0 0 140px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {a.cardName ?? a.cardId}
                  </span>

                  {/* 이상 내용 */}
                  <span style={{ fontSize: 12, color: '#64748b', flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {a.reason ?? '-'}
                  </span>

                  {/* 가격 */}
                  <span style={{ fontSize: 12, fontWeight: 700, color: '#dc2626', flexShrink: 0 }}>
                    {a.suspectPriceUsd ? `$${Number(a.suspectPriceUsd).toLocaleString()}` : ''}
                  </span>

                  {/* 소스 */}
                  <span style={{
                    fontSize: 10, fontWeight: 700, padding: '2px 6px', borderRadius: 6,
                    background: a.source === 'SCRYDEX_JP' ? '#eff6ff' : '#f0fdf4',
                    color: a.source === 'SCRYDEX_JP' ? '#1d4ed8' : '#15803d',
                    flexShrink: 0,
                  }}>{a.source}</span>
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* ── 스탯 카드 4개 ── */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 14, marginBottom: 16 }}>
        <StatCard icon={Users}          label="누적 유저"   color="indigo"
          value={stats?.totalUsers?.toLocaleString()}
          sub={`오늘 +${stats?.todayUsers ?? 0}명 신규`}
          delta={stats?.weeklyUserDelta} />
        <StatCard icon={CreditCard}     label="등록 카드"   color="cyan"
          value={stats?.totalCards?.toLocaleString()}
          sub="KO 기준 전체" />
        <StatCard icon={ScanLine}       label="누적 스캔"   color="emerald"
          value={stats?.totalScans?.toLocaleString()}
          sub={`오늘 ${stats?.todayScans ?? 0}회`}
          delta={stats?.weeklyScanDelta} />
        <StatCard icon={ArrowLeftRight} label="진행중 거래" color="amber"
          value={stats?.activeTrades?.toLocaleString()}
          sub="활성 거래글" />
      </div>

      {/* ── 차트 2열 ── */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, marginBottom: 16 }}>

        {/* 유저 추이 (Area) */}
        <div style={{ ...S.card, padding: '22px 24px' }}>
          <div style={S.h2}>유저 가입 추이 · 최근 7일</div>
          <ResponsiveContainer width="100%" height={180}>
            <AreaChart data={chartData} margin={{ top: 4, right: 4, left: -20, bottom: 0 }}>
              <defs>
                <linearGradient id="gUser" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%"  stopColor="#6366f1" stopOpacity={0.2} />
                  <stop offset="95%" stopColor="#6366f1" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" vertical={false} />
              <XAxis dataKey="day" tick={{ fontSize: 11, fill: '#94a3b8' }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fontSize: 11, fill: '#94a3b8' }} axisLine={false} tickLine={false} />
              <Tooltip content={<ChartTooltip unit="명" />} />
              <Area type="monotone" dataKey="신규유저" stroke="#6366f1" strokeWidth={2.5}
                fill="url(#gUser)" dot={{ r: 3, fill: '#6366f1', strokeWidth: 0 }} activeDot={{ r: 5 }} />
            </AreaChart>
          </ResponsiveContainer>
        </div>

        {/* 스캔 추이 (Bar) */}
        <div style={{ ...S.card, padding: '22px 24px' }}>
          <div style={S.h2}>스캔 횟수 · 최근 7일</div>
          <ResponsiveContainer width="100%" height={180}>
            <BarChart data={scanChart} margin={{ top: 4, right: 4, left: -20, bottom: 0 }} barSize={22}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" vertical={false} />
              <XAxis dataKey="day" tick={{ fontSize: 11, fill: '#94a3b8' }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fontSize: 11, fill: '#94a3b8' }} axisLine={false} tickLine={false} />
              <Tooltip content={<ChartTooltip unit="회" />} />
              <Bar dataKey="스캔수" fill="#06b6d4" radius={[6, 6, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* ── 하단 ── */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>

        {/* 서비스 상태 */}
        <div style={{ ...S.card, padding: '20px 24px' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
            <div style={S.h2}>서비스 상태</div>
            <span style={{ fontSize: 10, fontWeight: 700, color: '#6366f1', background: '#eef2ff', padding: '2px 8px', borderRadius: 99, textTransform: 'uppercase', letterSpacing: 0.5 }}>
              Live
            </span>
          </div>
          <ServiceRow name="Spring Boot API"  url="/health" />
          <ServiceRow name="FastAPI Scanner"  url="http://localhost:8082/health" />
          <ServiceRow name="FastAPI Grading"  url="http://localhost:8081/health" />
        </div>

        {/* 빠른 작업 */}
        <div style={{ ...S.card, padding: '20px 24px' }}>
          <div style={S.h2}>빠른 작업</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {[
              { href: '/cards',   label: '카드 추가하기',    sub: '새 카드 DB 등록',          dot: '#6366f1' },
              { href: '/users',   label: '유저 목록 보기',   sub: '전체 유저 조회·관리',       dot: '#06b6d4' },
              { href: '/price',   label: '시세 설정 확인',   sub: '환율·계수 현황',           dot: '#8b5cf6' },
              { href: '/scanner', label: '스캐너 확인',      sub: 'DINOv2 FAISS 인덱스 상태', dot: '#f59e0b' },
            ].map(({ href, label, sub, dot }) => (
              <a key={href} href={href} style={{
                display: 'flex', alignItems: 'center', gap: 12,
                padding: '10px 14px', borderRadius: 10,
                background: '#f8fafc', border: '1px solid #f1f5f9',
                textDecoration: 'none', transition: 'all 0.15s',
              }}
                onMouseEnter={e => { e.currentTarget.style.background = '#f1f5f9'; e.currentTarget.style.borderColor = '#e2e8f0' }}
                onMouseLeave={e => { e.currentTarget.style.background = '#f8fafc'; e.currentTarget.style.borderColor = '#f1f5f9' }}
              >
                <span style={{ width: 8, height: 8, borderRadius: '50%', background: dot, flexShrink: 0 }} />
                <div>
                  <div style={{ fontSize: 13, color: '#334155', fontWeight: 600 }}>{label}</div>
                  <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 1 }}>{sub}</div>
                </div>
              </a>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
