const eventLabels: Record<string, [string, string]> = {
  '222': ['二阶', '2×2×2'], '333': ['三阶', '3×3×3'], '444': ['四阶', '4×4×4'],
  '555': ['五阶', '5×5×5'], '666': ['六阶', '6×6×6'], '777': ['七阶', '7×7×7'],
  '333bld': ['三阶盲拧', '3×3×3 Blindfolded'], '333fm': ['三阶最少步', '3×3×3 Fewest Moves'],
  '333oh': ['三阶单手', '3×3×3 One-Handed'], '444bld': ['四阶盲拧', '4×4×4 Blindfolded'],
  '555bld': ['五阶盲拧', '5×5×5 Blindfolded'], '333mbld': ['三阶多盲', '3×3×3 Multi-Blind'],
  minx: ['五魔方', 'Megaminx'], pyram: ['金字塔', 'Pyraminx'], skewb: ['斜转', 'Skewb'],
}

const exampleAlgorithms: Record<string, string> = {
  pyram: "R U l b'", skewb: 'R U B', minx: 'R++ D-- U',
  sq1: '(1,0) / (0,3) /', clock: 'UR3+ y2 U2-', fto: 'U R BL BR',
}

export const stagedAssistMethods = new Set(['roux-s2', 'petrus-s2', 'cfop-f2l', 'zz-f2l', 'eo-dr'])

export const methodLabels: Record<string, [string, string]> = {
  cross: ['Cross 十字', 'Cross'], xcross: ['XCross 十字与一组 F2L', 'XCross'],
  eoline: ['EOline', 'EOline'], eofc: ['EOFC', 'EOFC'],
  'roux-s1': ['Roux 第一块', 'Roux first block'], 'roux-s2': ['Roux 分阶段', 'Roux stages'],
  'petrus-s1': ['Petrus 第一块', 'Petrus first block'], 'petrus-s2': ['Petrus 分阶段', 'Petrus stages'],
  'cfop-f2l': ['CFOP F2L 分阶段', 'CFOP F2L stages'], 'zz-f2l': ['ZZ F2L 分阶段', 'ZZ F2L stages'],
  'block-222': ['2×2×2 块', '2×2×2 block'], 'eo-dr': ['EO / DR 分阶段', 'EO / DR stages'],
  '333-two-phase': ['三阶两阶段完整求解', '3×3×3 two-phase solve'], '333-general': ['三阶自定义目标', '3×3×3 custom targets'],
  '222-face': ['二阶一面', '2×2×2 face'], '222-layer': ['二阶一层', '2×2×2 layer'],
  'sq1-shape-ftm': ['Square-1 形状 FTM', 'Square-1 shape FTM'],
  'sq1-shape-twist': ['Square-1 形状 Twist', 'Square-1 shape twist'],
  'pyraminx-v': ['金字塔 V', 'Pyraminx V'], 'skewb-face': ['斜转一面', 'Skewb face'],
}

export function eventLabel(event: string, english: boolean) {
  return eventLabels[event]?.[english ? 1 : 0] ?? { clock: 'Clock', sq1: 'Square-1', fto: 'FTO' }[event] ?? event
}

export function exampleAlgorithm(event: string) {
  return exampleAlgorithms[event] ?? "R U R' U'"
}

export function integerInRange(value: string | number, min: number, max: number) {
  const number = Number(value)
  if (value === '' || !Number.isInteger(number) || number < min || number > max) throw new RangeError(`${min}–${max}`)
  return number
}
