<script setup lang="ts">
import type { PresetDoc, PresetRow } from '~/utils/preset'
import { aspectRatioOf, CATEGORY_LABELS, emptyDoc, toSaveDoc, validateDoc } from '~/utils/preset'
import { prepareImage } from '~/utils/image'

const route = useRoute()
const { api, adminImageUrl } = useApi()
const toast = useToast()
const { extract, loading: extracting } = usePoseExtractor()

const isNew = computed(() => route.params.id === 'new')
const doc = ref<PresetDoc>(emptyDoc())
const row = ref<PresetRow | null>(null)
const loadError = ref('')

// 새로 고른 사진 (저장 시 업로드)
const newImage = ref<{ blob: Blob, url: string } | null>(null)
const opacity = ref(0.4)
const showJoints = ref(true)
const saving = ref(false)
const extractError = ref('')
const fileInput = ref<HTMLInputElement>()
const extractInfo = ref('')
const confirmDelete = ref(false)

const imageSrc = computed(() => {
  if (newImage.value) return newImage.value.url
  if (row.value?.image_etag) return adminImageUrl(row.value.id, row.value.image_etag)
  return undefined
})

const categoryItems = Object.entries(CATEGORY_LABELS).map(([value, label]) => ({ value, label }))
const errors = computed(() => validateDoc(doc.value, isNew.value))

async function load() {
  if (isNew.value) return
  try {
    row.value = await api<PresetRow>(`/admin/v1/presets/${route.params.id}`)
    doc.value = { ...emptyDoc(), ...row.value.doc, guide: row.value.doc.guide?.length ? [...row.value.doc.guide] : [''] }
  } catch (e) {
    loadError.value = apiErrorMessage(e)
  }
}
await load()

async function onFile(event: Event) {
  const file = (event.target as HTMLInputElement).files?.[0]
  if (!file) return
  extractError.value = ''
  extractInfo.value = ''
  try {
    const prepared = await prepareImage(file)
    if (newImage.value) URL.revokeObjectURL(newImage.value.url)
    newImage.value = { blob: prepared.blob, url: URL.createObjectURL(prepared.blob) }
    doc.value.aspect_ratio = aspectRatioOf(prepared.width, prepared.height)
    const result = await extract(prepared.canvas)
    doc.value.pose.landmarks = result.landmarks
    doc.value.outline = result.outline
    // 사진을 새로 올렸으면 앱 번들 사진 경로는 더 이상 쓰지 않는다
    delete doc.value.reference_asset
    extractInfo.value = `관절 ${result.visible}/33개 인식, 외곽선 점 ${result.outline.length}개 (${prepared.width}×${prepared.height}, ${(prepared.blob.size / 1024).toFixed(0)}KB)`
  } catch (e) {
    extractError.value = (e as Error).message
  } finally {
    (event.target as HTMLInputElement).value = ''
  }
}

function addStep() {
  doc.value.guide.push('')
}
function removeStep(i: number) {
  doc.value.guide.splice(i, 1)
  if (!doc.value.guide.length) doc.value.guide.push('')
}

async function save() {
  if (errors.value.length) return
  saving.value = true
  const body = { doc: toSaveDoc(doc.value), sort_order: doc.value.sort_order }
  try {
    if (isNew.value) {
      await api('/admin/v1/presets', { method: 'POST', body })
    } else {
      await api(`/admin/v1/presets/${doc.value.id}`, { method: 'PUT', body })
    }
    if (newImage.value) {
      await api(`/admin/v1/presets/${doc.value.id}/image`, {
        method: 'PUT',
        body: newImage.value.blob,
        headers: { 'Content-Type': 'image/jpeg' }
      })
    }
    toast.add({
      title: '저장했습니다',
      description: row.value?.status === 'published' ? '공개 중인 프리셋이라 앱에 바로 반영됩니다.' : '아직 비공개입니다. 오른쪽 위 [앱에 공개]를 누르면 앱에 보입니다.',
      color: 'success'
    })
    if (isNew.value) {
      await navigateTo(`/presets/${doc.value.id}`, { replace: true })
    }
    newImage.value = null
    await load()
  } catch (e) {
    toast.add({ title: '저장하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  } finally {
    saving.value = false
  }
}

async function setPublished(value: boolean) {
  if (!row.value) return
  try {
    await api(`/admin/v1/presets/${row.value.id}/status`, { method: 'PATCH', body: { status: value ? 'published' : 'draft' } })
    toast.add({ title: value ? '앱에 공개했습니다' : '비공개로 바꿨습니다', color: value ? 'success' : 'neutral' })
    await load()
  } catch (e) {
    toast.add({ title: '변경하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  }
}

async function remove() {
  try {
    await api(`/admin/v1/presets/${doc.value.id}`, { method: 'DELETE' })
    toast.add({ title: '삭제했습니다', color: 'neutral' })
    await navigateTo('/presets')
  } catch (e) {
    toast.add({ title: '삭제하지 못했습니다', description: apiErrorMessage(e), color: 'error' })
  } finally {
    confirmDelete.value = false
  }
}

onBeforeUnmount(() => {
  if (newImage.value) URL.revokeObjectURL(newImage.value.url)
})
</script>

<template>
  <UContainer class="py-8">
    <div class="mb-6 flex flex-wrap items-center justify-between gap-4">
      <div class="flex items-center gap-3">
        <UButton
          color="neutral"
          variant="ghost"
          icon="i-lucide-arrow-left"
          to="/presets"
          aria-label="목록으로"
        />
        <h1 class="text-2xl font-bold">
          {{ isNew ? '새 프리셋' : doc.title || doc.id }}
        </h1>
        <UBadge
          v-if="row"
          :color="row.status === 'published' ? 'success' : 'neutral'"
          variant="subtle"
          :label="row.status === 'published' ? '앱 공개 중' : '비공개'"
        />
      </div>
      <div class="flex gap-2">
        <UButton
          v-if="row"
          color="neutral"
          variant="outline"
          :label="row.status === 'published' ? '비공개로' : '앱에 공개'"
          :icon="row.status === 'published' ? 'i-lucide-eye-off' : 'i-lucide-eye'"
          @click="setPublished(row.status !== 'published')"
        />
        <UButton
          icon="i-lucide-save"
          label="저장"
          :loading="saving"
          :disabled="errors.length > 0 || extracting"
          @click="save"
        />
      </div>
    </div>

    <UAlert
      v-if="loadError"
      color="error"
      variant="subtle"
      :title="loadError"
      class="mb-4"
    />

    <div class="grid gap-8 lg:grid-cols-[minmax(0,480px)_1fr]">
      <!-- 사진·미리보기 -->
      <section class="space-y-4">
        <UCard>
          <template #header>
            <div class="font-semibold">
              1. 레퍼런스 사진
            </div>
            <p class="mt-1 text-sm text-muted">
              직접 촬영했거나 사용 권한이 있는 사진만 올려 주세요. 사진에서 관절과 인물 외곽선을 브라우저에서 바로 추출합니다.
            </p>
          </template>
          <input
            ref="fileInput"
            type="file"
            accept="image/jpeg,image/png,image/webp"
            class="hidden"
            :disabled="extracting"
            @change="onFile"
          >
          <!-- 실제 버튼이라 키보드(Tab·Enter)로도 사진을 고를 수 있다 -->
          <UButton
            icon="i-lucide-upload"
            :loading="extracting"
            :disabled="extracting"
            :label="extracting ? '포즈 추출 중… (처음엔 모델을 받느라 10초 정도 걸려요)' : '사진 선택'"
            @click="fileInput?.click()"
          />
          <p
            v-if="extractInfo"
            class="mt-3 text-sm text-success"
          >
            {{ extractInfo }}
          </p>
          <UAlert
            v-if="extractError"
            color="error"
            variant="subtle"
            :title="extractError"
            class="mt-3"
          />
        </UCard>

        <UCard>
          <template #header>
            <div class="font-semibold">
              앱 미리보기
            </div>
            <p class="mt-1 text-sm text-muted">
              앱 카메라 화면처럼 사진(투명도) 위에 인물 외곽선과 관절 점을 겹쳐 보여줍니다.
            </p>
          </template>
          <PosePreview
            :image-src="imageSrc"
            :aspect-ratio="doc.aspect_ratio"
            :outline="doc.outline"
            :landmarks="doc.pose.landmarks"
            :opacity="opacity"
            :show-joints="showJoints"
          />
          <div class="mt-4 flex flex-wrap items-center gap-6">
            <div class="flex min-w-48 flex-1 items-center gap-3">
              <span class="text-sm text-muted">사진 투명도</span>
              <USlider
                v-model="opacity"
                :min="0"
                :max="1"
                :step="0.05"
                class="flex-1"
              />
            </div>
            <USwitch
              v-model="showJoints"
              label="관절 점"
            />
          </div>
          <p class="mt-2 text-xs text-muted">
            비율 {{ doc.aspect_ratio }} · 관절 {{ doc.pose.landmarks.filter(l => l[2] >= 0.5).length }}/33 · 외곽선 점 {{ doc.outline.length }}
          </p>
        </UCard>
      </section>

      <!-- 정보 입력 -->
      <section class="space-y-4">
        <UCard>
          <template #header>
            <div class="font-semibold">
              2. 프리셋 정보
            </div>
          </template>
          <div class="grid gap-4 sm:grid-cols-2">
            <UFormField
              label="ID"
              :help="isNew ? '영문 소문자·숫자·하이픈. 만든 뒤에는 바꿀 수 없습니다.' : '바꿀 수 없습니다.'"
              required
            >
              <UInput
                v-model="doc.id"
                :disabled="!isNew"
                placeholder="예: mirror-selfie"
                class="w-full"
              />
            </UFormField>
            <UFormField
              label="제목"
              required
            >
              <UInput
                v-model="doc.title"
                placeholder="예: 거울 셀카"
                class="w-full"
              />
            </UFormField>
            <UFormField
              label="카테고리"
              required
            >
              <USelect
                v-model="doc.category"
                :items="categoryItems"
                class="w-full"
              />
            </UFormField>
            <UFormField
              label="정렬 순서"
              help="작을수록 앞에 보입니다."
            >
              <UInputNumber
                v-model="doc.sort_order"
                :min="0"
                :step="10"
                class="w-full"
              />
            </UFormField>
            <UFormField
              label="한 줄 팁"
              class="sm:col-span-2"
            >
              <UInput
                v-model="doc.tip"
                placeholder="예: 살짝 밑에서 찍으면 다리가 길어 보여요"
                class="w-full"
              />
            </UFormField>
            <UFormField
              label="권장 카메라 각도 (도)"
              help="0 = 수평. 음수 = 아래에서 위로 올려 찍기 (예: 전신샷 -12). 앱이 이 각도에 맞으면 초록색으로 알려줍니다."
              class="sm:col-span-2"
            >
              <UInputNumber
                v-model="doc.camera.pitch_deg"
                :min="-45"
                :max="45"
                class="w-40"
              />
            </UFormField>
          </div>
        </UCard>

        <UCard>
          <template #header>
            <div class="flex items-center justify-between">
              <div class="font-semibold">
                3. 단계별 촬영 가이드
              </div>
              <UButton
                size="sm"
                color="neutral"
                variant="outline"
                icon="i-lucide-plus"
                label="단계 추가"
                @click="addStep"
              />
            </div>
          </template>
          <ol class="space-y-2">
            <li
              v-for="(_, i) in doc.guide"
              :key="i"
              class="flex items-center gap-2"
            >
              <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-elevated text-xs">{{ i + 1 }}</span>
              <UInput
                v-model="doc.guide[i]"
                placeholder="예: 폰을 무릎 높이까지 낮춰요"
                class="flex-1"
              />
              <UButton
                color="neutral"
                variant="ghost"
                icon="i-lucide-x"
                :aria-label="`${i + 1}단계 삭제`"
                @click="removeStep(i)"
              />
            </li>
          </ol>
        </UCard>

        <UAlert
          v-if="errors.length"
          color="warning"
          variant="subtle"
          title="저장하려면 확인해 주세요"
          :description="errors.join(' ')"
        />

        <div
          v-if="row"
          class="flex justify-end"
        >
          <UButton
            color="error"
            variant="ghost"
            icon="i-lucide-trash-2"
            label="프리셋 삭제"
            @click="confirmDelete = true"
          />
        </div>
      </section>
    </div>

    <UModal
      v-model:open="confirmDelete"
      title="프리셋을 삭제할까요?"
      description="사진과 포즈 데이터가 함께 삭제되며 되돌릴 수 없습니다. 앱에서도 바로 사라집니다."
    >
      <template #footer>
        <div class="flex w-full justify-end gap-2">
          <UButton
            color="neutral"
            variant="outline"
            label="취소"
            @click="confirmDelete = false"
          />
          <UButton
            color="error"
            label="삭제"
            @click="remove"
          />
        </div>
      </template>
    </UModal>
  </UContainer>
</template>
