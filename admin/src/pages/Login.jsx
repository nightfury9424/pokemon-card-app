import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import api from '../api'

export default function Login() {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const navigate = useNavigate()

  async function handleDevLogin() {
    setLoading(true)
    setError('')
    try {
      const res = await api.post('/auth/dev/login')
      localStorage.setItem('admin_token', res.data.data.accessToken)
      navigate('/dashboard')
    } catch {
      setError('로그인에 실패했습니다. 서버 상태를 확인해주세요.')
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
      </div>

      {/* 오른쪽 로그인 */}
      <div style={{
        width: 420, background: '#f1f4f9',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: 40,
      }}>
        <div style={{ width: '100%' }}>
          <h2 style={{ fontSize: 22, fontWeight: 700, color: '#1e293b', marginBottom: 6 }}>로그인</h2>
          <p style={{ fontSize: 13, color: '#94a3b8', marginBottom: 32 }}>관리자 계정으로 로그인하세요</p>

          <div style={{
            background: '#fff', borderRadius: 16,
            padding: '28px', border: '1px solid #e8edf4',
            boxShadow: '0 4px 20px rgba(0,0,0,0.06)',
          }}>
            <button
              onClick={handleDevLogin}
              disabled={loading}
              style={{
                width: '100%', padding: '13px',
                borderRadius: 12, border: 'none', cursor: loading ? 'not-allowed' : 'pointer',
                background: loading ? '#818cf8' : 'linear-gradient(135deg, #6366f1 0%, #4f46e5 100%)',
                color: '#fff', fontSize: 14, fontWeight: 600,
                fontFamily: 'inherit', transition: 'all 0.15s',
                opacity: loading ? 0.7 : 1,
              }}
            >
              {loading ? '로그인 중...' : 'DEV 계정으로 로그인'}
            </button>

            {error && (
              <div style={{
                marginTop: 12, padding: '10px 14px', borderRadius: 10,
                background: '#fef2f2', border: '1px solid #fecaca',
                color: '#dc2626', fontSize: 12,
              }}>
                {error}
              </div>
            )}
          </div>

          <p style={{ textAlign: 'center', color: '#cbd5e1', fontSize: 11, marginTop: 20 }}>
            개발 환경 전용 로그인
          </p>
        </div>
      </div>
    </div>
  )
}
