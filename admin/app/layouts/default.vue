<script setup lang="ts">
const { user, logout } = useAuth()
const config = useRuntimeConfig()
const route = useRoute()

const nav = computed(() => [
  { label: '프리셋', icon: 'i-lucide-images', to: '/presets', active: route.path.startsWith('/presets') },
  { label: '모니터링 (Grafana)', icon: 'i-lucide-activity', to: config.public.grafanaUrl as string, target: '_blank' }
])
</script>

<template>
  <div class="min-h-screen">
    <UHeader
      v-if="user"
      :toggle="false"
    >
      <template #left>
        <NuxtLink
          to="/presets"
          class="flex items-center gap-2 font-bold"
        >
          <img
            src="/favicon.png"
            alt=""
            class="size-7 rounded-md"
          >
          라익찍스 관리자
        </NuxtLink>
      </template>
      <UNavigationMenu
        :items="nav"
        class="hidden sm:flex"
      />
      <template #right>
        <span class="hidden text-sm text-muted md:inline">{{ user.email }}</span>
        <UButton
          color="neutral"
          variant="ghost"
          icon="i-lucide-log-out"
          label="로그아웃"
          @click="logout"
        />
      </template>
    </UHeader>
    <UMain>
      <slot />
    </UMain>
  </div>
</template>
