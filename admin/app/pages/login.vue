<script setup lang="ts">
import type { AdminConfig } from '~/composables/useAuth'

declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize: (o: { client_id: string, callback: (r: { credential: string }) => void, ux_mode?: string }) => void
          renderButton: (el: HTMLElement, o: Record<string, unknown>) => void
        }
      }
    }
  }
}

const { api } = useApi()
const { loginWithGoogle, devLogin } = useAuth()
const toast = useToast()
const button = ref<HTMLElement>()
const config = ref<AdminConfig>()
const loading = ref(false)
const error = ref('')

async function onCredential(credential: string) {
  loading.value = true
  error.value = ''
  try {
    await loginWithGoogle(credential)
    toast.add({ title: '로그인했습니다', color: 'success' })
    await navigateTo('/presets')
  } catch (e) {
    error.value = apiErrorMessage(e)
  } finally {
    loading.value = false
  }
}

async function onDevLogin() {
  try {
    await devLogin()
    await navigateTo('/presets')
  } catch (e) {
    error.value = apiErrorMessage(e)
  }
}

function loadGsi(): Promise<void> {
  return new Promise((resolve, reject) => {
    if (window.google?.accounts) return resolve()
    const s = document.createElement('script')
    s.src = 'https://accounts.google.com/gsi/client'
    s.async = true
    s.onload = () => resolve()
    s.onerror = () => reject(new Error('Google 로그인 스크립트를 불러오지 못했습니다.'))
    document.head.appendChild(s)
  })
}

onMounted(async () => {
  try {
    config.value = await api<AdminConfig>('/admin/v1/config')
  } catch (e) {
    error.value = apiErrorMessage(e)
    return
  }
  if (!config.value.google_client_id) return
  try {
    await loadGsi()
    window.google!.accounts.id.initialize({
      client_id: config.value.google_client_id,
      callback: r => onCredential(r.credential)
    })
    if (button.value) {
      window.google!.accounts.id.renderButton(button.value, {
        theme: 'filled_black', size: 'large', text: 'signin_with', locale: 'ko', width: 280
      })
    }
  } catch (e) {
    error.value = (e as Error).message
  }
})
</script>

<template>
  <div class="flex min-h-screen items-center justify-center p-6">
    <UCard class="w-full max-w-sm">
      <div class="flex flex-col items-center gap-4 text-center">
        <img
          src="/favicon.png"
          alt=""
          class="size-16 rounded-2xl"
        >
        <div>
          <h1 class="text-xl font-bold">
            라익찍스 관리자
          </h1>
          <p class="mt-1 text-sm text-muted">
            관리자로 등록된 Google 계정만 로그인할 수 있습니다.
          </p>
        </div>
        <div
          ref="button"
          class="min-h-11"
        />
        <UProgress
          v-if="loading"
          animation="carousel"
          class="w-40"
        />
        <UButton
          v-if="config?.dev_login"
          color="neutral"
          variant="outline"
          icon="i-lucide-wrench"
          label="개발용 로그인 (로컬 전용)"
          @click="onDevLogin"
        />
        <UAlert
          v-if="error"
          color="error"
          variant="subtle"
          :title="error"
          class="text-left"
        />
      </div>
    </UCard>
  </div>
</template>
