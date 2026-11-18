import { describe, expect, it } from 'vitest'
import { largestRegion, maskToOutline, simplifyClosed } from '../app/utils/outline'

function rectMask(w: number, h: number, rects: [number, number, number, number][]) {
  const m = new Float32Array(w * h)
  for (const [x0, y0, x1, y1] of rects) {
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) m[y * w + x] = 0.9
  }
  return m
}

describe('maskToOutline', () => {
  it('사각형 마스크 → 네 꼭짓점 근처 점들만 남음', () => {
    const outline = maskToOutline(rectMask(100, 100, [[20, 30, 79, 69]]), 100, 100)
    expect(outline.length).toBeGreaterThanOrEqual(4)
    expect(outline.length).toBeLessThanOrEqual(8)
    const xs = outline.map(p => p[0])
    const ys = outline.map(p => p[1])
    expect(Math.min(...xs)).toBeCloseTo(0.2, 2)
    expect(Math.max(...xs)).toBeCloseTo(0.79, 2)
    expect(Math.min(...ys)).toBeCloseTo(0.3, 2)
    expect(Math.max(...ys)).toBeCloseTo(0.69, 2)
  })

  it('여러 영역이면 가장 큰 영역(인물)만 사용', () => {
    const mask = rectMask(100, 100, [[2, 2, 8, 8], [40, 40, 90, 95]])
    const outline = maskToOutline(mask, 100, 100)
    expect(Math.min(...outline.map(p => p[0]))).toBeGreaterThan(0.35)
  })

  it('사람이 없으면 빈 배열', () => {
    expect(maskToOutline(new Float32Array(100), 10, 10)).toEqual([])
  })

  it('모든 좌표는 0~1', () => {
    const outline = maskToOutline(rectMask(50, 80, [[0, 0, 49, 79]]), 50, 80)
    for (const [x, y] of outline) {
      expect(x).toBeGreaterThanOrEqual(0)
      expect(x).toBeLessThanOrEqual(1)
      expect(y).toBeGreaterThanOrEqual(0)
      expect(y).toBeLessThanOrEqual(1)
    }
  })

  it('L자 모양도 오목한 꼭짓점을 유지', () => {
    // ㄴ자: 세로 막대 + 아래 가로 막대
    const outline = maskToOutline(rectMask(100, 100, [[10, 10, 30, 90], [10, 70, 90, 90]]), 100, 100)
    expect(outline.length).toBeGreaterThanOrEqual(6)
    // 오목한 안쪽 꼭짓점(약 0.31, 0.69) 근처 점이 있어야 함
    expect(outline.some(([x, y]) => Math.abs(x - 0.31) < 0.03 && Math.abs(y - 0.69) < 0.03)).toBe(true)
  })
})

describe('largestRegion / simplifyClosed', () => {
  it('임계값 미만은 무시', () => {
    const m = new Float32Array(25).fill(0.3)
    expect(largestRegion(m, 5, 5, 0.5)).toBeNull()
  })

  it('일직선 위의 점은 제거', () => {
    const pts: [number, number][] = [[0, 0], [5, 0], [10, 0], [10, 10], [5, 10], [0, 10]]
    expect(simplifyClosed(pts, 0.5).length).toBe(4)
  })
})
