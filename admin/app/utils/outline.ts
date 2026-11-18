/**
 * 인물 분할 마스크 → 인물 외곽선 (프레임 기준 0~1 좌표).
 *
 * 1) 임계값으로 이진화 2) 가장 큰 연결 영역(인물)만 남김 3) Moore-Neighbor 경계 추적
 * 4) Douglas-Peucker 단순화 (오차 = 둘레 × epsilonRatio, 오프라인 추출과 같은 0.0012)
 */
export type Point = [number, number]

export interface OutlineOptions {
  threshold?: number
  epsilonRatio?: number
}

export function maskToOutline(mask: ArrayLike<number>, width: number, height: number, opts: OutlineOptions = {}): Point[] {
  const threshold = opts.threshold ?? 0.5
  const epsilonRatio = opts.epsilonRatio ?? 0.0012
  const region = largestRegion(mask, width, height, threshold)
  if (!region) return []
  const contour = traceBoundary(region, width, height)
  if (contour.length < 3) return []
  const simplified = simplifyClosed(contour, epsilonRatio * perimeter(contour))
  return simplified.map(([x, y]) => [round4(x / width), round4(y / height)])
}

/** 가장 큰 4-연결 영역을 1로 표시한 배열 (없으면 null) */
export function largestRegion(mask: ArrayLike<number>, w: number, h: number, threshold: number): Uint8Array | null {
  const label = new Int32Array(w * h)
  let best = 0
  let bestSize = 0
  let next = 0
  const queue = new Int32Array(w * h)
  for (let i = 0; i < w * h; i++) {
    if (label[i] !== 0 || mask[i]! < threshold) continue
    next++
    let head = 0
    let tail = 0
    queue[tail++] = i
    label[i] = next
    while (head < tail) {
      const p = queue[head++]!
      const x = p % w
      const y = (p - x) / w
      const neighbors = [x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1, y > 0 ? p - w : -1, y < h - 1 ? p + w : -1]
      for (const n of neighbors) {
        if (n >= 0 && label[n] === 0 && mask[n]! >= threshold) {
          label[n] = next
          queue[tail++] = n
        }
      }
    }
    if (tail > bestSize) {
      bestSize = tail
      best = next
    }
  }
  if (best === 0) return null
  const out = new Uint8Array(w * h)
  for (let i = 0; i < w * h; i++) out[i] = label[i] === best ? 1 : 0
  return out
}

// 시계 방향 8방향 (오른쪽부터)
const DIRS: Point[] = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]

/** Moore-Neighbor 경계 추적 (가장 위·왼쪽 픽셀에서 시작해 시작점으로 돌아올 때까지) */
export function traceBoundary(region: Uint8Array, w: number, h: number): Point[] {
  const at = (x: number, y: number) => x >= 0 && y >= 0 && x < w && y < h && region[y * w + x] === 1
  let start = -1
  for (let i = 0; i < w * h; i++) {
    if (region[i] === 1) {
      start = i
      break
    }
  }
  if (start < 0) return []
  const sx = start % w
  const sy = (start - sx) / w
  const points: Point[] = [[sx, sy]]
  let cx = sx
  let cy = sy
  // 시작점에 왼쪽(빈칸)에서 오른쪽으로 들어왔다고 본다
  let dir = 0
  const maxSteps = 4 * w * h
  for (let step = 0; step < maxSteps; step++) {
    let found = false
    for (let k = 0; k < 8; k++) {
      // 온 쪽(dir+4)의 바로 다음 칸부터 시계 방향으로 탐색 (Moore-Neighbor)
      const d = (dir + 5 + k) % 8
      const nx = cx + DIRS[d]![0]
      const ny = cy + DIRS[d]![1]
      if (at(nx, ny)) {
        cx = nx
        cy = ny
        dir = d
        found = true
        break
      }
    }
    if (!found) break // 단일 픽셀
    if (cx === sx && cy === sy) break
    points.push([cx, cy])
  }
  return points
}

export function perimeter(pts: Point[]): number {
  let sum = 0
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i]!
    const b = pts[(i + 1) % pts.length]!
    sum += Math.hypot(b[0] - a[0], b[1] - a[1])
  }
  return sum
}

/** 폐곡선 Douglas-Peucker: 가장 먼 두 점으로 나눠 각각 단순화 */
export function simplifyClosed(pts: Point[], epsilon: number): Point[] {
  if (pts.length < 4) return pts
  let far = 0
  let farDist = -1
  for (let i = 1; i < pts.length; i++) {
    const d = Math.hypot(pts[i]![0] - pts[0]![0], pts[i]![1] - pts[0]![1])
    if (d > farDist) {
      farDist = d
      far = i
    }
  }
  const a = rdp(pts.slice(0, far + 1), epsilon)
  const b = rdp([...pts.slice(far), pts[0]!], epsilon)
  return [...a.slice(0, -1), ...b.slice(0, -1)]
}

function rdp(pts: Point[], epsilon: number): Point[] {
  if (pts.length < 3) return pts
  const [ax, ay] = pts[0]!
  const [bx, by] = pts[pts.length - 1]!
  const len = Math.hypot(bx - ax, by - ay) || 1
  let idx = 0
  let max = 0
  for (let i = 1; i < pts.length - 1; i++) {
    const [px, py] = pts[i]!
    const d = Math.abs((by - ay) * px - (bx - ax) * py + bx * ay - by * ax) / len
    if (d > max) {
      max = d
      idx = i
    }
  }
  if (max <= epsilon) return [pts[0]!, pts[pts.length - 1]!]
  return [...rdp(pts.slice(0, idx + 1), epsilon).slice(0, -1), ...rdp(pts.slice(idx), epsilon)]
}

const round4 = (v: number) => Math.round(v * 10000) / 10000
