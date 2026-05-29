import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// 2026-05-29: prod 배포 — nginx 가 /admin/ 아래 SPA static 서빙.
//   asset path (script/css) 가 /admin/assets/... 로 resolve 되도록 base 변경.
//   local dev (npm run dev)는 https://localhost:5173/ 그대로 동작 (Vite dev server는 base를 dev에서도 사용).
//   BrowserRouter 의 basename={import.meta.env.BASE_URL} 도 함께 설정 필요 (App.jsx).
export default defineConfig({
  plugins: [react(), tailwindcss()],
  base: '/admin/',
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:8080',
    },
  },
})
