export interface PreparedImage {
  canvas: HTMLCanvasElement
  blob: Blob
  width: number
  height: number
}

const MAX_BYTES = 1500 * 1024

/**
 * 긴 변 maxSide 이하로 줄인 크기. 폭은 4의 배수로 맞춘다.
 * MediaPipe Pose Landmarker(CPU, 마스크 출력)는 폭이 4의 배수가 아니면 WASM이 중단(Aborted)된다
 * (예: 1059×1080 실패, 1060×1080 정상. 높이는 홀수여도 정상). 최대 3px 잘려 비율 차이는 무시할 수준.
 */
export function fitSize(srcWidth: number, srcHeight: number, maxSide = 1080): { width: number, height: number } {
  const scale = Math.min(1, maxSide / Math.max(srcWidth, srcHeight))
  const width = Math.max(4, Math.floor(Math.round(srcWidth * scale) / 4) * 4)
  const height = Math.max(1, Math.round(srcHeight * scale))
  return { width, height }
}

/** 사진을 긴 변 maxSide 이하로 줄여 JPEG로 (서버 업로드 한도 1.5MB 이내) */
export async function prepareImage(file: File, maxSide = 1080): Promise<PreparedImage> {
  const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' })
  const { width, height } = fitSize(bitmap.width, bitmap.height, maxSide)
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, width, height)
  bitmap.close()

  let quality = 0.88
  let blob = await toBlob(canvas, quality)
  while (blob.size > MAX_BYTES && quality > 0.5) {
    quality -= 0.1
    blob = await toBlob(canvas, quality)
  }
  return { canvas, blob, width, height }
}

function toBlob(canvas: HTMLCanvasElement, quality: number): Promise<Blob> {
  return new Promise((resolve, reject) =>
    canvas.toBlob(b => (b ? resolve(b) : reject(new Error('이미지 변환 실패'))), 'image/jpeg', quality)
  )
}
