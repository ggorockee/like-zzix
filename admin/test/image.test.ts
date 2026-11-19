import { describe, expect, it } from 'vitest'
import { fitSize } from '../app/utils/image'

describe('fitSize', () => {
  it('긴 변을 maxSide로 줄이고 폭은 4의 배수 (MediaPipe 중단 방지)', () => {
    // 3529×3600 세로 사진 → 1059×1080이 아니라 1056×1080
    expect(fitSize(3529, 3600)).toEqual({ width: 1056, height: 1080 })
  })

  it('가로 사진도 폭은 4의 배수, 높이는 그대로', () => {
    expect(fitSize(3600, 3529)).toEqual({ width: 1080, height: 1059 })
  })

  it('작은 사진은 키우지 않고 폭만 4의 배수로 내림', () => {
    expect(fitSize(803, 601)).toEqual({ width: 800, height: 601 })
  })

  it('폭이 4보다 작아도 최소 4', () => {
    expect(fitSize(2, 10)).toEqual({ width: 4, height: 10 })
  })

  it('모든 결과 폭은 4의 배수', () => {
    for (let w = 500; w < 4000; w += 37) {
      expect(fitSize(w, 3000).width % 4).toBe(0)
    }
  })
})
