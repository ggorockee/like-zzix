import type { FetchError } from 'ofetch'

/** Go API 호출. 세션 쿠키(lzx_admin)를 함께 보낸다. */
export function useApi() {
  const config = useRuntimeConfig()
  const base = config.public.apiBase as string

  const api = $fetch.create({
    baseURL: base,
    credentials: 'include',
    async onResponseError({ request, response }) {
      // 세션 확인(/me)은 미들웨어가 직접 처리하므로 여기서 이동하지 않는다
      if (response.status !== 401 || String(request).endsWith('/admin/v1/me')) return
      useAuth().user.value = null
      if (useRouter().currentRoute.value.path !== '/login') await navigateTo('/login')
    }
  })

  /** 관리자 미리보기용 사진 주소 (초안 사진 포함, 쿠키로 인증) */
  const adminImageUrl = (id: string, etag?: string) =>
    `${base}/admin/v1/presets/${encodeURIComponent(id)}/image${etag ? `?v=${etag}` : ''}`

  return { api, base, adminImageUrl }
}

/** 서버 오류 메시지를 사람이 읽을 문장으로 */
export function apiErrorMessage(e: unknown): string {
  const err = e as FetchError<{ error?: string }>
  const status = err?.response?.status
  const msg = err?.data?.error
  switch (status) {
    case 401: return '로그인이 필요합니다.'
    case 403: return '관리자 권한이 없는 계정입니다.'
    case 409: return '같은 ID의 프리셋이 이미 있습니다.'
    case 413: return '사진이 너무 큽니다 (최대 1.5MB).'
    case 415: return 'JPEG, PNG, WebP 사진만 올릴 수 있습니다.'
    case 422: return `입력값을 확인해 주세요: ${msg ?? ''}`
    case 429: return '로그인 시도가 너무 많습니다. 1분 뒤 다시 시도해 주세요.'
    case 503: return '서버 또는 데이터베이스에 연결할 수 없습니다.'
  }
  return msg ?? '요청을 처리하지 못했습니다.'
}
