import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import Layout from './components/Layout'
import Dashboard from './pages/Dashboard'
import Cards from './pages/Cards'
import Users from './pages/Users'
import Trades from './pages/Trades'
import Price from './pages/Price'
import Scanner from './pages/Scanner'
import Login from './pages/Login'
import Alerts from './pages/Alerts'
import Reports from './pages/Reports'

function RequireAuth({ children }) {
  const token = localStorage.getItem('admin_token')
  return token ? children : <Navigate to="/login" replace />
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/" element={<RequireAuth><Layout /></RequireAuth>}>
          <Route index element={<Navigate to="/dashboard" replace />} />
          <Route path="dashboard" element={<Dashboard />} />
          <Route path="cards" element={<Cards />} />
          <Route path="users" element={<Users />} />
          <Route path="trades" element={<Trades />} />
          <Route path="price" element={<Price />} />
          <Route path="scanner" element={<Scanner />} />
          <Route path="alerts" element={<Alerts />} />
          <Route path="reports" element={<Reports />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}
