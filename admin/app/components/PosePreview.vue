<script setup lang="ts">
// 앱 카메라 화면과 같은 방식으로 미리보기: 레퍼런스 사진(투명도) + 인물 외곽선 + 관절 점
const props = withDefaults(defineProps<{
  imageSrc?: string
  aspectRatio: string
  outline: [number, number][]
  landmarks: [number, number, number][]
  opacity?: number
  showJoints?: boolean
}>(), { opacity: 0.4, showJoints: true, imageSrc: undefined })

const canvas = ref<HTMLCanvasElement>()
const img = ref<HTMLImageElement | null>(null)

const ratio = computed(() => {
  const [w, h] = props.aspectRatio.split(':').map(Number)
  return w && h ? w / h : 3 / 4
})

watch(() => props.imageSrc, (src) => {
  img.value = null
  if (!src) return draw()
  const el = new Image()
  el.crossOrigin = 'use-credentials'
  el.onload = () => {
    img.value = el
    draw()
  }
  el.onerror = () => draw()
  el.src = src
}, { immediate: true })

watch(() => [props.outline, props.landmarks, props.opacity, props.showJoints, ratio.value], () => draw(), { deep: true })
onMounted(draw)

// 비교 관절 13개 (앱 PoseMatcher와 동일)
const JOINTS = [0, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]

function draw() {
  const c = canvas.value
  if (!c) return
  const width = 480
  const height = Math.round(width / ratio.value)
  // 고해상도 화면에서 흐려지지 않게 기기 픽셀 비율만큼 그린다
  const dpr = Math.min(3, Math.max(2, window.devicePixelRatio || 1))
  c.width = Math.round(width * dpr)
  c.height = Math.round(height * dpr)
  // 높이를 px로 고정하면 화면이 좁을 때 max-w-full로 폭만 줄어 사진이 가로로 찌그러진다.
  // 높이는 auto로 두어 캔버스 고유 비율(width/height 속성)을 그대로 따르게 한다.
  c.style.width = `${width}px`
  c.style.height = 'auto'
  const ctx = c.getContext('2d')!
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  ctx.imageSmoothingQuality = 'high'
  ctx.fillStyle = '#18181b'
  ctx.fillRect(0, 0, width, height)

  if (img.value) {
    ctx.globalAlpha = props.opacity
    ctx.drawImage(img.value, 0, 0, width, height)
    ctx.globalAlpha = 1
  }

  if (props.outline.length >= 3) {
    ctx.save()
    ctx.strokeStyle = 'white'
    ctx.lineWidth = 2.5
    ctx.lineJoin = 'round'
    ctx.shadowColor = 'rgba(255,255,255,0.8)'
    ctx.shadowBlur = 8
    ctx.beginPath()
    props.outline.forEach(([x, y], i) => (i ? ctx.lineTo(x * width, y * height) : ctx.moveTo(x * width, y * height)))
    ctx.closePath()
    ctx.stroke()
    ctx.restore()
  }

  if (props.showJoints) {
    for (const i of JOINTS) {
      const l = props.landmarks[i]
      if (!l || l[2] < 0.5) continue
      ctx.beginPath()
      ctx.arc(l[0] * width, l[1] * height, 4, 0, Math.PI * 2)
      ctx.fillStyle = '#34C759'
      ctx.fill()
      ctx.lineWidth = 1.5
      ctx.strokeStyle = 'rgba(0,0,0,0.6)'
      ctx.stroke()
    }
  }
}
</script>

<template>
  <canvas
    ref="canvas"
    class="max-w-full rounded-lg border border-default"
  />
</template>
