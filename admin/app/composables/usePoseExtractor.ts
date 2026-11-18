import type { PoseLandmarker } from '@mediapipe/tasks-vision'
import { maskToOutline, type Point } from '~/utils/outline'

// package.json의 @mediapipe/tasks-vision 버전과 맞춘다 (wasm 파일)
const TASKS_VISION_VERSION = '1.2.3'
// 오프라인 추출(레퍼런스 프리셋)과 같은 모델 → 같은 기준의 좌표
const MODEL_URL = 'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task'

export interface PoseExtraction {
  landmarks: [number, number, number][]
  outline: Point[]
  visible: number
}

let landmarker: Promise<PoseLandmarker> | null = null

// 사진 1장씩 처리하므로 CPU로 충분하고 안정적 (GPU는 마스크가 WebGL 텍스처라 별도 캔버스 문맥 필요)
async function create(): Promise<PoseLandmarker> {
  const { FilesetResolver, PoseLandmarker } = await import('@mediapipe/tasks-vision')
  const fileset = await FilesetResolver.forVisionTasks(
    `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${TASKS_VISION_VERSION}/wasm`
  )
  return PoseLandmarker.createFromOptions(fileset, {
    baseOptions: { modelAssetPath: MODEL_URL, delegate: 'CPU' },
    runningMode: 'IMAGE',
    numPoses: 1,
    outputSegmentationMasks: true
  })
}

/** 브라우저에서 레퍼런스 사진의 관절 33개와 인물 외곽선을 추출 (모델은 처음 한 번만 받음) */
export function usePoseExtractor() {
  const loading = ref(false)

  async function getLandmarker() {
    landmarker ??= create()
    try {
      return await landmarker
    } catch (e) {
      landmarker = null
      throw e
    }
  }

  async function extract(image: HTMLCanvasElement): Promise<PoseExtraction> {
    if (!hasWebGL()) {
      throw new Error('이 브라우저에서 WebGL(그래픽 가속)을 쓸 수 없어 포즈를 추출할 수 없습니다. '
        + 'Chrome 설정 > 시스템 > "가능한 경우 그래픽 가속 사용"을 켜고 브라우저를 다시 시작해 주세요.')
    }
    loading.value = true
    try {
      const lm = await getLandmarker()
      return await new Promise<PoseExtraction>((resolve, reject) => {
        lm.detect(image, (result) => {
          // 마스크는 콜백 안에서만 유효하므로 여기서 모두 꺼낸다
          const pose = result.landmarks[0]
          const mask = result.segmentationMasks?.[0]
          if (!pose || !mask) {
            reject(new Error('사진에서 사람을 찾지 못했습니다. 전신 또는 상반신이 잘 보이는 사진을 써 주세요.'))
            return
          }
          const landmarks = pose.map(p => [round4(p.x), round4(p.y), round3(p.visibility ?? 0)] as [number, number, number])
          const outline = maskToOutline(mask.getAsFloat32Array(), mask.width, mask.height)
          resolve({ landmarks, outline, visible: landmarks.filter(l => l[2] >= 0.5).length })
        })
      })
    } finally {
      loading.value = false
    }
  }

  return { extract, loading }
}

/** MediaPipe 웹 라이브러리는 CPU 모드에서도 WebGL로 이미지를 변환한다 */
export function hasWebGL(): boolean {
  try {
    const c = document.createElement('canvas')
    return !!(c.getContext('webgl2') || c.getContext('webgl'))
  } catch {
    return false
  }
}

const round4 = (v: number) => Math.round(v * 10000) / 10000
const round3 = (v: number) => Math.round(v * 1000) / 1000
