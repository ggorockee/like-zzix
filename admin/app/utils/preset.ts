/** 앱·서버와 같은 프리셋 스키마 (claudedocs/planning/01_MOBILE.md 5장) */
export interface PresetDoc {
  id: string
  category: string
  title: string
  tip: string
  guide: string[]
  aspect_ratio: string
  camera: { pitch_deg: number, roll_deg: number }
  pose: { format: 'blazepose33', coord: 'normalized', landmarks: [number, number, number][] }
  outline: [number, number][]
  sort_order: number
  reference_asset?: string
  updated_at?: string
  [key: string]: unknown
}

/** 서버 관리자 API의 프리셋 행 */
export interface PresetRow {
  id: string
  doc: PresetDoc
  status: 'draft' | 'published'
  sort_order: number
  image_etag?: string
  image_type?: string
  updated_at: string
  updated_by: string
}

// id는 저장된 문서와 호환되도록 그대로 두고, 이름은 앱 탭과 맞춘다
export const CATEGORY_LABELS: Record<string, string> = {
  full_body: '기본/인물',
  cafe: '배경/여행',
  look_back: '포즈/느낌',
  side: '특수/2인'
}

export const ID_PATTERN = /^[a-z0-9][a-z0-9-]{0,62}$/

/** 가로세로 픽셀 → "가로:세로" (최대공약수로 약분) */
export function aspectRatioOf(width: number, height: number): string {
  const gcd = (a: number, b: number): number => (b === 0 ? a : gcd(b, a % b))
  const g = gcd(width, height) || 1
  return `${width / g}:${height / g}`
}

export function emptyDoc(): PresetDoc {
  return {
    id: '',
    category: 'full_body',
    title: '',
    tip: '',
    guide: [''],
    aspect_ratio: '3:4',
    camera: { pitch_deg: 0, roll_deg: 0 },
    pose: { format: 'blazepose33', coord: 'normalized', landmarks: [] },
    outline: [],
    sort_order: 100
  }
}

/** 저장 전 정리: 빈 가이드 단계 제거, 서버가 붙이는 필드 제외 */
export function toSaveDoc(doc: PresetDoc): PresetDoc {
  const out: PresetDoc = { ...doc, guide: doc.guide.map(s => s.trim()).filter(Boolean) }
  delete out.reference_url
  delete out.updated_at
  return out
}

/** 저장 가능 여부 (서버 검증과 같은 기준을 먼저 화면에서 안내) */
export function validateDoc(doc: PresetDoc, isNew: boolean): string[] {
  const errors: string[] = []
  if (isNew && !ID_PATTERN.test(doc.id)) errors.push('ID는 영문 소문자·숫자·하이픈(-)만 쓸 수 있습니다.')
  if (!doc.title.trim()) errors.push('제목을 입력해 주세요.')
  if (!CATEGORY_LABELS[doc.category]) errors.push('카테고리를 선택해 주세요.')
  if (doc.pose.landmarks.length !== 33) errors.push('사진을 올려 포즈(관절 33개)를 추출해 주세요.')
  return errors
}
