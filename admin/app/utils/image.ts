export interface PreparedImage {
  canvas: HTMLCanvasElement
  blob: Blob
  width: number
  height: number
}

const MAX_BYTES = 1500 * 1024

/** 사진을 긴 변 maxSide 이하로 줄여 JPEG로 (서버 업로드 한도 1.5MB 이내) */
export async function prepareImage(file: File, maxSide = 1080): Promise<PreparedImage> {
  const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' })
  const scale = Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height))
  const width = Math.round(bitmap.width * scale)
  const height = Math.round(bitmap.height * scale)
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
