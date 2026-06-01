// 2026-05-29: Google OAuth web flow (사용자 명시 A+i 진행).
//   prod 는 DEV_LOGIN_ENABLED=false 라 기존 /api/auth/dev/login 호출은 막힘 (403).
//   Google Identity Services (gsi/client) 스크립트 + g_id_signin button.
//   ID token 발급 → POST /api/auth/google/token → JWT → admin_token localStorage.
//   AdminAllowlistFilter (백엔드) 가 진짜 권한 게이트 — ADMIN_USER_IDS 에 없으면 admin 메뉴 403.
//
//   환경변수: VITE_GOOGLE_WEB_CLIENT_ID (build 시 주입).
//     예: VITE_GOOGLE_WEB_CLIENT_ID=<web-client-id>.apps.googleusercontent.com npm run build
//     또는 admin/.env.production 파일.

import { useEffect, useState, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import api from '../api'

const GOOGLE_CLIENT_ID = import.meta.env.VITE_GOOGLE_WEB_CLIENT_ID || ''
const GSI_SCRIPT = 'https://accounts.google.com/gsi/client'

export default function Login() {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [gsiReady, setGsiReady] = useState(false)
  const navigate = useNavigate()
  const buttonRef = useRef(null)

  useEffect(() => {
    if (!GOOGLE_CLIENT_ID) {
      setError('VITE_GOOGLE_WEB_CLIENT_ID 환경변수가 설정되지 않았습니다. .env.production 또는 build 시 주입 필요.')
      return
    }
    // GSI script 1회 로드 (이미 있으면 skip).
    const existing = document.querySelector(`script[src="${GSI_SCRIPT}"]`)
    if (existing) {
      initGsi()
      return
    }
    const s = document.createElement('script')
    s.src = GSI_SCRIPT
    s.async = true
    s.defer = true
    s.onload = initGsi
    s.onerror = () => setError('Google Identity Services 로드 실패')
    document.body.appendChild(s)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  function initGsi() {
    if (!window.google || !window.google.accounts || !window.google.accounts.id) {
      setError('Google Identity Services 초기화 실패')
      return
    }
    window.google.accounts.id.initialize({
      client_id: GOOGLE_CLIENT_ID,
      callback: handleCredential,
      use_fedcm_for_prompt: false,
    })
    if (buttonRef.current) {
      window.google.accounts.id.renderButton(buttonRef.current, {
        type: 'standard',
        theme: 'filled_blue',
        size: 'large',
        text: 'signin_with',
        shape: 'rectangular',
        logo_alignment: 'left',
        width: 340,
      })
    }
    setGsiReady(true)
  }

  async function handleCredential(response) {
    const idToken = response?.credential
    if (!idToken) {
      setError('ID token 발급 실패')
      return
    }
    setLoading(true)
    setError('')
    try {
      const res = await api.post('/auth/google/token', { idToken })
      const accessToken = res.data?.data?.accessToken
      if (!accessToken) throw new Error('accessToken 누락')
      localStorage.setItem('admin_token', accessToken)
      // admin 권한 즉시 확인 — 비-admin이면 dashboard 진입 시 메뉴 호출 403.
      try {
        await api.get('/admin/whoami')
        navigate('/dashboard')
      } catch (e) {
        if (e.response?.status === 403) {
          setError('관리자 권한이 없는 계정입니다. ADMIN_USER_IDS allowlist 에 등록되어야 합니다.')
          localStorage.removeItem('admin_token')
        } else {
          // whoami 일시 오류는 dashboard 진입 시도.
          navigate('/dashboard')
        }
      }
    } catch (e) {
      const msg = e.response?.data?.message ?? e.message ?? '로그인에 실패했습니다.'
      setError(msg)
      localStorage.removeItem('admin_token')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{
      minHeight: '100vh', display: 'flex',
      background: 'linear-gradient(135deg, #4c1d95 0%, #3730a3 100%)',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    }}>
      {/* 왼쪽 브랜딩 */}
      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column',
        justifyContent: 'center', padding: '60px 80px',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 48 }}>
          <div style={{
            width: 44, height: 44, borderRadius: 12,
            background: 'rgba(255,255,255,0.15)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <span style={{ color: '#fff', fontSize: 20, fontWeight: 800 }}>P</span>
          </div>
          <span style={{ color: '#fff', fontSize: 18, fontWeight: 700 }}>포켓폴리오</span>
        </div>
        <h1 style={{ color: '#fff', fontSize: 40, fontWeight: 800, lineHeight: 1.2, letterSpacing: -1, marginBottom: 16 }}>
          Admin ERP<br />대시보드
        </h1>
        <p style={{ color: 'rgba(255,255,255,0.6)', fontSize: 15, lineHeight: 1.6 }}>
          포켓폴리오 서비스의 운영 현황,<br />
          카드·유저·거래를 한 곳에서 관리하세요.
        </p>
        <p style={{ color: 'rgba(255,255,255,0.4)', fontSize: 12, marginTop: 24, lineHeight: 1.6 }}>
          관리자 권한은 Google 로그인 후 백엔드 allowlist 로 검증됩니다.<br />
          비-관리자 계정으로 로그인 시 메뉴가 표시되지 않습니다.
        </p>
      </div>

      {/* 오른쪽 로그인 */}
      <div style={{
        width: 420, background: '#f1f4f9',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: 40,
      }}>
        <div style={{ width: '100%' }}>
          <h2 style={{ fontSize: 22, fontWeight: 700, color: '#1e293b', marginBottom: 6 }}>로그인</h2>
          <p style={{ fontSize: 13, color: '#94a3b8', marginBottom: 32 }}>Google 계정으로 로그인하세요</p>

          <div style={{
            background: '#fff', borderRadius: 16,
            padding: '28px', border: '1px solid #e8edf4',
            boxShadow: '0 4px 20px rgba(0,0,0,0.06)',
          }}>
            {!GOOGLE_CLIENT_ID ? (
              <div style={{
                padding: '14px 16px', borderRadius: 10,
                background: '#fef2f2', border: '1px solid #fecaca',
                color: '#dc2626', fontSize: 12, lineHeight: 1.5,
              }}>
                <strong>설정 필요</strong><br />
                Google Cloud Console 에서 OAuth Web Client ID 발급 후<br />
                <code style={{ background: '#fff', padding: '2px 6px', borderRadius: 4, fontSize: 11 }}>VITE_GOOGLE_WEB_CLIENT_ID</code>
                {' '}환경변수에 설정해주세요.
              </div>
            ) : (
              <>
                {/* Google Identity Services 가 여기에 button render */}
                <div ref={buttonRef} style={{ display: 'flex', justifyContent: 'center' }} />
                {!gsiReady && (
                  <p style={{ textAlign: 'center', color: '#94a3b8', fontSize: 12, marginTop: 12 }}>
                    Google 로그인 버튼 로딩 중...
                  </p>
                )}
                {loading && (
                  <p style={{ textAlign: 'center', color: '#4f46e5', fontSize: 13, fontWeight: 600, marginTop: 16 }}>
                    로그인 처리 중...
                  </p>
                )}
              </>
            )}

            {error && (
              <div style={{
                marginTop: 12, padding: '10px 14px', borderRadius: 10,
                background: '#fef2f2', border: '1px solid #fecaca',
                color: '#dc2626', fontSize: 12, lineHeight: 1.5,
              }}>
                {error}
              </div>
            )}
          </div>

          <p style={{ textAlign: 'center', color: '#cbd5e1', fontSize: 11, marginTop: 20 }}>
            관리자 권한이 필요합니다
          </p>
        </div>
      </div>
    </div>
  )
}
