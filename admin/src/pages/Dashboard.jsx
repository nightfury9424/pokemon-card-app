import { useEffect, useState, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { Users, CreditCard, ArrowLeftRight, RefreshCw, TrendingUp, TrendingDown, AlertTriangle, ExternalLink, ScrollText, Flag, Mail, ShieldAlert, ChevronRight } from 'lucide-react'
import {
  AreaChart, Area,
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

/* ── 스탯 카드 ──
   2026-05-29 P-1: delta 는 명시 prop 일 때만 노출. 0% / NaN / 분모0 이면 무조건 chip 숨김.
   "누적 유저" 같은 누적 카드에는 delta prop 자체 안 넘긴다 (의미 mismatch 방지). */
function StatCard({ icon: Icon, label, value, sub, delta, color, onClick }) {
  const palette = {
    indigo: '#6366f1', cyan: '#06b6d4', emerald: '#10b981', amber: '#f59e0b', red: '#ef4444', violet: '#8b5cf6',
  }
  const c = palette[color] ?? palette.indigo
  // 가드: null / undefined / NaN / 0 모두 chip 미표시. "변화 없음 / 데이터 없음" 을 0%↑ 로 잘못 보여주는 것 방지.
  const showDelta = typeof delta === 'number' && Number.isFinite(delta) && delta !== 0
  const isUp = delta > 0

  return (
    <div onClick={onClick}
      style={{ ...S.card, padding: '20px 22px', cursor: onClick ? 'pointer' : 'default', transition: 'box-shadow .15s, transform .15s' }}
      onMouseEnter={onClick ? e => { e.currentTarget.style.boxShadow = '0 6px 20px rgba(0,0,0,0.10)'; e.currentTarget.style.transform = 'translateY(-1px)' } : undefined}
      onMouseLeave={onClick ? e => { e.currentTarget.style.boxShadow = S.card.boxShadow; e.currentTarget.style.transform = 'none' } : undefined}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 14 }}>
        <div style={{ width: 38, height: 38, borderRadius: 10, background: c + '18', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon size={17} color={c} strokeWidth={2} />
        </div>
        {showDelta && (
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

/* ── 서비스 상태 ──
   2026-05-29 P0 #2: 브라우저 직접 호출 제거. 백엔드 /admin/services-status 1회 호출.
   상태 분류 (Codex 사전 Q2):
     RUNNING        — 초록   (enabled=true + reachable)
     DOWN           — 빨강   (enabled=true + unreachable, 진짜 장애)
     DISABLED       — 노랑   (enabled=false, 일부러 꺼둠)
     NOT_CONFIGURED — 회색   (url 설정 자체 없음) */
const SVC_LOOK = {
  RUNNING:        { dot: '#22c55e', label: 'Running',         text: '#16a34a' },
  DOWN:           { dot: '#ef4444', label: 'Down',            text: '#dc2626' },
  DISABLED:       { dot: '#f59e0b', label: 'Disabled',        text: '#d97706' },
  NOT_CONFIGURED: { dot: '#94a3b8', label: 'Not configured',  text: '#64748b' },
  CHECKING:       { dot: '#cbd5e1', label: 'Checking',        text: '#94a3b8' },
}
function ServiceDot({ status }) {
  const c = SVC_LOOK[status]?.dot ?? SVC_LOOK.CHECKING.dot
  return (
    <span style={{
      width: 8, height: 8, borderRadius: '50%', background: c,
      boxShadow: `0 0 6px ${c}80`,
      display: 'inline-block',
    }} />
  )
}
function ServiceRow({ svc }) {
  const s = SVC_LOOK[svc.status] ?? SVC_LOOK.CHECKING
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '11px 0', borderBottom: '1px solid #f8fafc' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <ServiceDot status={svc.status} />
        <span style={{ fontSize: 13, color: '#475569', fontWeight: 500 }}>{svc.name}</span>
      </div>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
        <span style={{ fontSize: 12, fontWeight: 600, color: s.text }}>{s.label}</span>
        {typeof svc.responseMs === 'number' && svc.status === 'RUNNING' && (
          <span style={{ fontSize: 11, color: '#cbd5e1' }}>{svc.responseMs}ms</span>
        )}
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

// 2026-06-07 최근 운영 로그 위젯 — admin_actions 액션/대상 한글 라벨.
const ADMIN_ACTION_LABEL = {
  SUSPEND: '정지', UNSUSPEND: '정지 해제', WARN: '경고', AUTO_SUSPEND: '자동 정지',
  DELETE_TRADE: '거래글 삭제', DELETE_CHAT_MESSAGE: '채팅 삭제',
  REVIEW_REPORT: '신고 처리', DISMISS_REPORT: '신고 기각', RESOLVE_ANOMALY: '이상가 처리',
}
const TARGET_LABEL = { USER: '유저', TRADE: '거래글', REPORT: '신고', CHAT_MESSAGE: '채팅', PRICE_ANOMALY: '가격이상' }

/* ── 메인 ── */
export default function Dashboard() {
  const navigate = useNavigate()
  const [stats,     setStats]     = useState(null)
  const [chartData, setChartData] = useState([])
  const [recentActions, setRecentActions] = useState([])  // 2026-06-07: 미연동 스캔 차트 대체
  const [spinning,  setSpinning]  = useState(false)
  const [alerts,    setAlerts]    = useState([])   // 미처리 이상 알림
  const [chartDays, setChartDays] = useState(30)   // P0 #1: 7d/30d 토글 default 30d.
  const [services,  setServices]  = useState([])   // P0 #2: backend services-status 응답.
  const [queue,     setQueue]     = useState(null) // 운영 대기 큐 (신고/문의/이의신청/가격이상)
  const [anomalyTotal, setAnomalyTotal] = useState(0) // 가격이상 미처리 총량(배너용)

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
        hiddenCards:  ca.value?.data?.data?.hidden ?? 0,   // P-1: @SQLRestriction 으로 가려진 row 수.
        weeklyUserDelta: u.value?.data?.data?.weeklyDelta ?? null,
        weeklyScanDelta: sc.value?.data?.data?.weeklyDelta ?? null,
      })
    })

    /* 운영 대기 큐 카운트 — 기존 API 재사용 (신고 pendingCount / 문의·이의신청 OPEN list len / 가격이상 totalElements) */
    Promise.allSettled([
      api.get('/admin/reports', { params: { page: 0, size: 1 } }),
      api.get('/admin/inquiries', { params: { status: 'OPEN', excludeCategory: 'SUSPENSION_APPEAL' } }),
      api.get('/admin/inquiries', { params: { status: 'OPEN', category: 'SUSPENSION_APPEAL' } }),
      api.get('/admin/price-anomalies', { params: { resolved: false, page: 0, size: 1 } }),
    ]).then(([rep, inq, app, ano]) => {
      const anoTotal = ano.value?.data?.data?.totalElements ?? 0
      setQueue({
        reports:   rep.value?.data?.data?.pendingCount ?? 0,
        inquiries: (inq.value?.data?.data ?? []).length,
        appeals:   (app.value?.data?.data ?? []).length,
        anomalies: anoTotal,
      })
      setAnomalyTotal(anoTotal)
    })

    /* 유저 추이 차트 — P0 #1: 누적 + 신규 분리. days param. */
    api.get('/admin/stats/users/chart', { params: { days: chartDays } })
      .then(r => setChartData(r.data?.data ?? []))
      .catch(() => setChartData([]))

    /* 최근 운영 로그 (admin_actions) — 2026-06-07: scan_logs 미연동 스캔 차트 대체.
       스캔 사용 추이는 user_events(Phase 2) 연동 후 복원 예정. */
    api.get('/admin/admin-actions', { params: { page: 0, size: 6 } })
      .then(r => setRecentActions(r.data?.data?.content ?? []))
      .catch(() => setRecentActions([]))
      .finally(() => setSpinning(false))
  }, [chartDays])

  useEffect(() => { load() }, [load])

  /* 2026-05-29 Codex 사후 Q6: services-status 는 chartDays 토글과 무관해야 함.
     mount 1회 + 새로고침 버튼 클릭 시만 재호출. backend 가 3개 health probe 병렬 호출하므로
     필요 이상 빈번한 호출은 ForkJoin/scanner 부담. */
  const loadServices = useCallback(() => {
    api.get('/admin/services-status')
      .then(r => setServices(r.data?.data?.services ?? []))
      .catch(() => setServices([]))
  }, [])
  useEffect(() => { loadServices() }, [loadServices])

  return (
    <div style={S.page}>

      {/* ── 헤더 ── */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 22 }}>
        <div>
          <div style={{ fontSize: 22, fontWeight: 700, color: '#1e293b', letterSpacing: -0.5 }}>대시보드</div>
          <div style={{ fontSize: 13, color: '#94a3b8', marginTop: 3 }}>포켓폴리오 운영 현황 · 실시간</div>
        </div>
        <button
          onClick={() => { load(); loadServices() }}
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
                가격 이상 — 미처리 {anomalyTotal.toLocaleString()}건 · 최근 {alerts.length}건 표시
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

      {/* ── 운영 대기 큐 4개 (2026-06-11: 성장지표→운영큐 전환) ──
         출시직후/sparse 에도 의미있고 매일 행동할 지표. 카드 클릭 = 해당 처리 페이지.
         죽은 "누적 스캔(미연동)" 제거. 성장/카탈로그는 아래 보조 strip 으로. */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 14, marginBottom: 14 }}>
        <StatCard icon={Flag}          label="신고 대기"        color="red"    onClick={() => navigate('/reports')}
          value={queue?.reports?.toLocaleString()}   sub="확인·처리 필요" />
        <StatCard icon={Mail}          label="문의 대기"        color="cyan"   onClick={() => navigate('/inquiries')}
          value={queue?.inquiries?.toLocaleString()} sub="답변 대기" />
        <StatCard icon={ShieldAlert}   label="정지 이의신청"    color="violet" onClick={() => navigate('/appeals')}
          value={queue?.appeals?.toLocaleString()}   sub="검토 대기" />
        <StatCard icon={AlertTriangle} label="가격 이상 미처리" color="amber"  onClick={() => navigate('/alerts')}
          value={queue?.anomalies?.toLocaleString()} sub="검토 필요" />
      </div>

      {/* ── 보조 현황 strip (성장/카탈로그 — 매일 행동지표 아님, 작게) ── */}
      <div style={{ ...S.card, display: 'flex', alignItems: 'center', padding: '12px 4px', marginBottom: 16 }}>
        {[
          { icon: Users,          label: '누적 유저',   value: stats?.totalUsers?.toLocaleString(),  sub: `오늘 +${stats?.todayUsers ?? 0}` },
          { icon: CreditCard,     label: '등록 카드',   value: stats?.totalCards?.toLocaleString(),  sub: stats?.hiddenCards > 0 ? `감춤 ${stats.hiddenCards.toLocaleString()}` : 'KO 노출' },
          { icon: ArrowLeftRight, label: '진행중 거래', value: stats?.activeTrades?.toLocaleString(), sub: '활성 거래글' },
        ].map((m, i) => (
          <div key={m.label} style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 11, padding: '4px 18px', borderLeft: i > 0 ? '1px solid #f1f5f9' : 'none' }}>
            <div style={{ width: 32, height: 32, borderRadius: 9, background: '#f1f5f9', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              <m.icon size={15} color="#94a3b8" strokeWidth={2} />
            </div>
            <div style={{ minWidth: 0 }}>
              <div style={{ fontSize: 19, fontWeight: 800, color: '#334155', lineHeight: 1.1 }}>{m.value ?? '—'}</div>
              <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 2 }}>{m.label} · {m.sub}</div>
            </div>
          </div>
        ))}
      </div>

      {/* ── 차트 2열 ── */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, marginBottom: 16 }}>

        {/* 유저 추이 — 2026-05-29 P0 #1: 누적 + 일별 신규 분리. 7d/30d 토글. */}
        <div style={{ ...S.card, padding: '22px 24px' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
            <div style={S.h2}>유저 가입 추이 · 최근 {chartDays}일</div>
            <div style={{ display: 'flex', gap: 4 }}>
              {[7, 30].map(d => (
                <button key={d} onClick={() => setChartDays(d)} style={{
                  padding: '4px 10px', fontSize: 11, fontWeight: 700, borderRadius: 6,
                  border: '1px solid', cursor: 'pointer', fontFamily: 'inherit',
                  background: chartDays === d ? '#6366f1' : '#fff',
                  color: chartDays === d ? '#fff' : '#64748b',
                  borderColor: chartDays === d ? '#6366f1' : '#e2e8f0',
                }}>{d}d</button>
              ))}
            </div>
          </div>
          <ResponsiveContainer width="100%" height={200}>
            <AreaChart data={chartData} margin={{ top: 4, right: 4, left: -20, bottom: 0 }}>
              <defs>
                <linearGradient id="gUser" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%"  stopColor="#6366f1" stopOpacity={0.25} />
                  <stop offset="95%" stopColor="#6366f1" stopOpacity={0} />
                </linearGradient>
                <linearGradient id="gCum" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%"  stopColor="#10b981" stopOpacity={0.18} />
                  <stop offset="95%" stopColor="#10b981" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" vertical={false} />
              <XAxis dataKey="day" tick={{ fontSize: 10, fill: '#94a3b8' }} axisLine={false} tickLine={false}
                interval={chartDays === 30 ? 4 : 0} />
              <YAxis yAxisId="left" tick={{ fontSize: 11, fill: '#94a3b8' }} axisLine={false} tickLine={false} />
              <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 11, fill: '#10b981' }} axisLine={false} tickLine={false} />
              <Tooltip content={<ChartTooltip unit="명" />} />
              <Legend wrapperStyle={{ fontSize: 11, paddingTop: 4 }} iconType="circle" />
              <Area yAxisId="left" type="monotone" dataKey="신규유저" name="일별 신규" stroke="#6366f1" strokeWidth={2.5}
                fill="url(#gUser)" dot={{ r: 2, fill: '#6366f1', strokeWidth: 0 }} activeDot={{ r: 5 }} />
              <Area yAxisId="right" type="monotone" dataKey="누적" name="누적 유저" stroke="#10b981" strokeWidth={2}
                fill="url(#gCum)" dot={false} activeDot={{ r: 4 }} strokeDasharray="3 3" />
            </AreaChart>
          </ResponsiveContainer>
        </div>

        {/* 최근 운영 로그 — 2026-06-07: 미연동 스캔 차트 대체. admin_actions 최근 6건.
            (스캔 사용 추이는 user_events Phase 2 연동 후 별도 복원) */}
        <div style={{ ...S.card, padding: '22px 24px' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14 }}>
            <div style={{ ...S.h2, marginBottom: 0 }}>최근 운영 로그</div>
            <button onClick={() => navigate('/admin-actions')} style={{
              display: 'flex', alignItems: 'center', gap: 4,
              padding: '5px 10px', borderRadius: 8, border: '1px solid #e2e8f0',
              background: '#fff', color: '#64748b', fontSize: 11, fontWeight: 600, cursor: 'pointer', fontFamily: 'inherit',
            }}>전체 보기 <ExternalLink size={11} /></button>
          </div>
          {recentActions.length === 0 ? (
            <div style={{ fontSize: 12, color: '#94a3b8', padding: '44px 0', textAlign: 'center', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
              <ScrollText size={14} /> 아직 운영 액션 기록이 없어요 · 신고·문의·가격이상 처리 시 기록돼요
            </div>
          ) : (
            <div>
              {recentActions.map(a => (
                <div key={a.actionId} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 0', borderBottom: '1px solid #f8fafc' }}>
                  <span style={{ fontSize: 10, fontWeight: 700, padding: '2px 7px', borderRadius: 99, background: '#eef2ff', color: '#4f46e5', whiteSpace: 'nowrap', flexShrink: 0 }}>
                    {ADMIN_ACTION_LABEL[a.actionType] ?? a.actionType}
                  </span>
                  <span style={{ flex: 1, fontSize: 12, color: '#475569', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {(a.adminNickname || a.adminUserId)} · {TARGET_LABEL[a.targetType] ?? a.targetType} {a.targetId}
                  </span>
                  <span style={{ fontSize: 11, color: '#cbd5e1', flexShrink: 0, fontVariantNumeric: 'tabular-nums' }}>
                    {a.createdAt ? new Date(a.createdAt).toLocaleDateString('ko-KR', { month: '2-digit', day: '2-digit' }) : ''}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* ── 하단 ── */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>

        {/* 서비스 상태 — 2026-05-29 P0 #2: backend /admin/services-status 1회 호출. */}
        <div style={{ ...S.card, padding: '20px 24px' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
            <div style={S.h2}>서비스 상태</div>
            <span style={{ fontSize: 10, fontWeight: 700, color: '#6366f1', background: '#eef2ff', padding: '2px 8px', borderRadius: 99, textTransform: 'uppercase', letterSpacing: 0.5 }}>
              Live
            </span>
          </div>
          {services.length === 0 ? (
            <div style={{ fontSize: 12, color: '#94a3b8', padding: '20px 0', textAlign: 'center' }}>점검 중…</div>
          ) : services.map(svc => (
            <ServiceRow key={svc.name} svc={svc} />
          ))}
          <div style={{ fontSize: 10, color: '#cbd5e1', marginTop: 6 }}>
            Disabled = 운영 정책상 꺼둠 · Down = 켜져 있어야 하는데 응답 없음 · Not configured = URL 미설정
          </div>
        </div>

        {/* 빠른 작업 — 2026-05-29 P0 #4: 실제 운영 메뉴 4개로 교체. */}
        <div style={{ ...S.card, padding: '20px 24px' }}>
          <div style={S.h2}>빠른 작업</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {/* ops 대기 큐는 상단 카드가 전담 → 빠른작업은 관리 페이지 네비(중복 회피). */}
            {[
              { href: '/users',  label: '유저 관리', sub: '닉네임/이메일 조회·정지',  dot: '#06b6d4' },
              { href: '/trades', label: '거래 관리', sub: '거래글 목록·admin 삭제',  dot: '#8b5cf6' },
              { href: '/cards',  label: '카드 관리', sub: '카탈로그·노출 관리',       dot: '#10b981' },
              { href: '/price',  label: '시세 관리', sub: '가격·계수 확인',           dot: '#f59e0b' },
            ].map(({ href, label, sub, dot }) => (
              <div key={href} onClick={() => navigate(href)} style={{
                display: 'flex', alignItems: 'center', gap: 12,
                padding: '10px 14px', borderRadius: 10,
                background: '#f8fafc', border: '1px solid #f1f5f9',
                cursor: 'pointer', transition: 'all 0.15s',
              }}
                onMouseEnter={e => { e.currentTarget.style.background = '#f1f5f9'; e.currentTarget.style.borderColor = '#e2e8f0' }}
                onMouseLeave={e => { e.currentTarget.style.background = '#f8fafc'; e.currentTarget.style.borderColor = '#f1f5f9' }}
              >
                <span style={{ width: 8, height: 8, borderRadius: '50%', background: dot, flexShrink: 0 }} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 13, color: '#334155', fontWeight: 600 }}>{label}</div>
                  <div style={{ fontSize: 11, color: '#94a3b8', marginTop: 1 }}>{sub}</div>
                </div>
                <ChevronRight size={15} color="#cbd5e1" style={{ flexShrink: 0 }} />
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
