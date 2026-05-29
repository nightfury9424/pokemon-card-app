import { Outlet, NavLink, useNavigate, useLocation } from 'react-router-dom'
import { useEffect, useState } from 'react'
import {
  LayoutDashboard, CreditCard, Users, ArrowLeftRight,
  TrendingUp, ScanLine, LogOut, AlertTriangle, Flag
} from 'lucide-react'
import api from '../api'

const nav = [
  { to: '/dashboard', icon: LayoutDashboard, label: '대시보드' },
  { to: '/reports',   icon: Flag,            label: '신고 처리', reportBadge: true },
  { to: '/users',     icon: Users,           label: '유저 관리' },
  { to: '/trades',    icon: ArrowLeftRight,  label: '거래 관리' },
  { to: '/cards',     icon: CreditCard,      label: '카드 관리' },
  { to: '/price',     icon: TrendingUp,      label: '시세 관리' },
  { to: '/scanner',   icon: ScanLine,        label: '스캐너' },
  { to: '/alerts',    icon: AlertTriangle,   label: '가격 이상', alertBadge: true },
]

export default function Layout() {
  const navigate = useNavigate()
  const location = useLocation()
  const [alertCount, setAlertCount] = useState(0)
  const [reportCount, setReportCount] = useState(0)

  useEffect(() => {
    api.get('/admin/price-anomalies', { params: { resolved: false, page: 0, size: 1 } })
      .then(r => setAlertCount(r.data?.data?.totalElements ?? 0))
      .catch(() => {})
    // 2026-05-29 admin Stage 0 — 신고 PENDING count sidebar badge.
    api.get('/admin/reports', { params: { status: 'PENDING', page: 0, size: 1 } })
      .then(r => setReportCount(r.data?.data?.pendingCount ?? 0))
      .catch(() => {})
  }, [location.pathname])

  function logout() {
    localStorage.removeItem('admin_token')
    navigate('/login')
  }

  return (
    <div style={{ display: 'flex', height: '100vh', overflow: 'hidden', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' }}>

      {/* ── 사이드바 ── */}
      <aside style={{
        width: 210,
        minWidth: 210,
        display: 'flex',
        flexDirection: 'column',
        background: 'linear-gradient(180deg, #4c1d95 0%, #3730a3 50%, #312e81 100%)',
      }}>

        {/* 로고 */}
        <div style={{ padding: '28px 20px 20px', display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{
            width: 36, height: 36, borderRadius: 10, background: 'rgba(255,255,255,0.15)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          }}>
            <span style={{ color: '#fff', fontSize: 16, fontWeight: 800 }}>P</span>
          </div>
          <div>
            <div style={{ color: '#fff', fontSize: 13, fontWeight: 700, letterSpacing: -0.2 }}>포켓폴리오</div>
            <div style={{ color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 1 }}>Admin ERP</div>
          </div>
        </div>

        {/* 메뉴 */}
        <nav style={{ flex: 1, padding: '8px 12px', overflowY: 'auto' }}>
          {nav.map(({ to, icon: Icon, label, alertBadge, reportBadge }) => {
            const active = location.pathname === to
            const badgeCount = alertBadge ? alertCount : reportBadge ? reportCount : 0
            const showBadge = badgeCount > 0
            return (
              <NavLink
                key={to}
                to={to}
                style={{
                  display: 'flex', alignItems: 'center', gap: 10,
                  padding: '10px 12px', borderRadius: 10, marginBottom: 2,
                  fontSize: 13, textDecoration: 'none',
                  background: active ? 'rgba(255,255,255,0.15)' : 'transparent',
                  color: active ? '#fff' : showBadge ? '#fca5a5' : 'rgba(255,255,255,0.55)',
                  fontWeight: active || showBadge ? 600 : 400,
                  transition: 'all 0.15s',
                }}
                onMouseEnter={e => { if (!active) e.currentTarget.style.background = 'rgba(255,255,255,0.08)'; e.currentTarget.style.color = '#fff' }}
                onMouseLeave={e => { if (!active) { e.currentTarget.style.background = 'transparent'; e.currentTarget.style.color = showBadge ? '#fca5a5' : 'rgba(255,255,255,0.55)' } }}
              >
                <Icon size={15} strokeWidth={active ? 2.5 : 2} />
                <span style={{ flex: 1 }}>{label}</span>
                {showBadge && (
                  <span style={{
                    fontSize: 10, fontWeight: 800, padding: '2px 6px',
                    borderRadius: 99, background: '#dc2626', color: '#fff',
                    minWidth: 18, textAlign: 'center',
                  }}>{badgeCount > 99 ? '99+' : badgeCount}</span>
                )}
              </NavLink>
            )
          })}
        </nav>

        {/* 팁 박스 */}
        <div style={{
          margin: '0 12px 12px',
          background: 'rgba(255,255,255,0.08)',
          borderRadius: 12, padding: '12px 14px',
        }}>
          <div style={{ color: 'rgba(255,255,255,0.5)', fontSize: 10, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8, marginBottom: 6 }}>운영 현황</div>
          <div style={{ color: 'rgba(255,255,255,0.8)', fontSize: 12, lineHeight: 1.5 }}>
            서비스가 정상 운영 중입니다. 새 기능을 추가하려면 카드 관리를 이용하세요.
          </div>
        </div>

        {/* 로그아웃 */}
        <div style={{ padding: '12px', borderTop: '1px solid rgba(255,255,255,0.1)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 12px', marginBottom: 6 }}>
            <div style={{
              width: 30, height: 30, borderRadius: '50%',
              background: 'rgba(255,255,255,0.2)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <span style={{ color: '#fff', fontSize: 12, fontWeight: 700 }}>A</span>
            </div>
            <div>
              <div style={{ color: '#fff', fontSize: 12, fontWeight: 500 }}>관리자</div>
              <div style={{ color: 'rgba(255,255,255,0.4)', fontSize: 10 }}>admin</div>
            </div>
          </div>
          <button
            onClick={logout}
            style={{
              width: '100%', display: 'flex', alignItems: 'center', gap: 10,
              padding: '9px 12px', borderRadius: 10, border: 'none', cursor: 'pointer',
              background: 'rgba(255,255,255,0.08)', color: 'rgba(255,255,255,0.6)', fontSize: 13,
              transition: 'all 0.15s',
            }}
            onMouseEnter={e => { e.currentTarget.style.background = 'rgba(239,68,68,0.2)'; e.currentTarget.style.color = '#fca5a5' }}
            onMouseLeave={e => { e.currentTarget.style.background = 'rgba(255,255,255,0.08)'; e.currentTarget.style.color = 'rgba(255,255,255,0.6)' }}
          >
            <LogOut size={14} />
            로그아웃
          </button>
        </div>
      </aside>

      {/* ── 메인 콘텐츠 ── */}
      <main style={{ flex: 1, overflow: 'auto', background: '#f1f4f9', minWidth: 0 }}>
        <Outlet />
      </main>
    </div>
  )
}
