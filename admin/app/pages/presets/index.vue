<script setup lang="ts">
import type { PresetRow } from '~/utils/preset'
import { CATEGORY_LABELS } from '~/utils/preset'

const { api, adminImageUrl } = useApi()
const toast = useToast()

const { data, refresh, status, error } = await useAsyncData('admin-presets', () =>
  api<{ items: PresetRow[] }>('/admin/v1/presets')
)
const rows = computed(() => data.value?.items ?? [])
const publishedCount = computed(() => rows.value.filter(r => r.status === 'published').length)

const columns = [
  { accessorKey: 'image', header: '사진' },
  { accessorKey: 'title', header: '프리셋' },
  { accessorKey: 'category', header: '카테고리' },
  { accessorKey: 'status', header: '앱 공개' },
  { accessorKey: 'sort_order', header: '정렬' },
  { accessorKey: 'updated', header: '최근 수정' },
  { accessorKey: 'actions', header: '' }
]

const busy = ref<string | null>(null)

async function togglePublish(row: PresetRow, value: boolean) {
  busy.value = row.id
  try {
    await api(`/admin/v1/presets/${row.id}/status`, {
      method: 'PATCH',
      body: { status: value ? 'published' : 'draft' }
    })
    toast.add({
      title: value ? `"${row.doc.title}" 공개` : `"${row.doc.title}" 비공개`,
      description: value ? '앱이 다음에 프리셋을 불러올 때 보입니다.' : '앱 목록에서 빠집니다.',
      color: value ? 'success' : 'neutral'
    })
    await refresh()
  } catch (e) {
    toast.add({ title: '변경하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  } finally {
    busy.value = null
  }
}

const fmt = (iso: string) => new Date(iso).toLocaleString('ko-KR', { dateStyle: 'short', timeStyle: 'short' })
</script>

<template>
  <UContainer class="py-8">
    <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-2xl font-bold">
          구도 프리셋
        </h1>
        <p class="mt-1 text-sm text-muted">
          전체 {{ rows.length }}개 · 앱 공개 {{ publishedCount }}개. 공개한 프리셋만 앱에 보입니다.
        </p>
      </div>
      <UButton
        icon="i-lucide-plus"
        label="새 프리셋"
        to="/presets/new"
      />
    </div>

    <UAlert
      v-if="error"
      color="error"
      variant="subtle"
      :title="apiErrorMessage(error)"
      class="mb-4"
    />

    <UTable
      :data="rows"
      :columns="columns"
      :loading="status === 'pending'"
      empty="프리셋이 없습니다."
      class="rounded-lg border border-default"
    >
      <template #image-cell="{ row }">
        <img
          v-if="row.original.image_etag"
          :src="adminImageUrl(row.original.id, row.original.image_etag)"
          alt=""
          class="size-14 rounded-md object-cover"
          crossorigin="use-credentials"
        >
        <div
          v-else
          class="flex size-14 items-center justify-center rounded-md bg-elevated text-xs text-muted"
        >
          윤곽선만
        </div>
      </template>
      <template #title-cell="{ row }">
        <NuxtLink
          :to="`/presets/${row.original.id}`"
          class="font-medium hover:underline"
        >
          {{ row.original.doc.title }}
        </NuxtLink>
        <div class="text-xs text-muted">
          {{ row.original.id }}
        </div>
      </template>
      <template #category-cell="{ row }">
        <UBadge
          color="neutral"
          variant="subtle"
          :label="CATEGORY_LABELS[row.original.doc.category] ?? row.original.doc.category"
        />
      </template>
      <template #status-cell="{ row }">
        <USwitch
          :model-value="row.original.status === 'published'"
          :loading="busy === row.original.id"
          :label="row.original.status === 'published' ? '공개' : '비공개'"
          @update:model-value="(v: boolean) => togglePublish(row.original, v)"
        />
      </template>
      <template #updated-cell="{ row }">
        <div class="text-sm">
          {{ fmt(row.original.updated_at) }}
        </div>
        <div class="text-xs text-muted">
          {{ row.original.updated_by }}
        </div>
      </template>
      <template #actions-cell="{ row }">
        <UButton
          color="neutral"
          variant="ghost"
          icon="i-lucide-pencil"
          label="편집"
          :to="`/presets/${row.original.id}`"
        />
      </template>
    </UTable>
  </UContainer>
</template>
