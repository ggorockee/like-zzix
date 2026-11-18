export interface AdminUser { email: string }
export interface AdminConfig { google_client_id: string, categories: string[], dev_login: boolean }

export function useAuth() {
  const user = useState<AdminUser | null>('admin-user', () => null)
  const checked = useState('admin-user-checked', () => false)
  const { api } = useApi()

  /** 세션 확인 (앱 시작 시 1회) */
  async function refresh() {
    try {
      user.value = await api<AdminUser>('/admin/v1/me')
    } catch {
      user.value = null
    } finally {
      checked.value = true
    }
  }

  async function loginWithGoogle(credential: string) {
    user.value = await api<AdminUser>('/admin/v1/auth/google', { method: 'POST', body: { credential } })
  }

  /** 로컬 개발 전용 (서버가 APP_ENV=local일 때만 존재) */
  async function devLogin() {
    user.value = await api<AdminUser>('/admin/v1/auth/dev', { method: 'POST' })
  }

  async function logout() {
    try {
      await api('/admin/v1/auth/logout', { method: 'POST' })
    } finally {
      user.value = null
      await navigateTo('/login')
    }
  }

  return { user, checked, refresh, loginWithGoogle, devLogin, logout }
}
