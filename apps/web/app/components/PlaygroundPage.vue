<script setup lang="ts">
import { Check, Copy, Link2, FastForward, Pause, Play, Rewind, RotateCcw } from '@lucide/vue'
import type { AssistOptions, EventInfo, TrainingOptions } from 'cubegin'
import type { AsyncEngine, WorkerClient } from 'cubegin/worker'
import type { SiteLanguage } from '#shared/utils/site-seo'
import { Button } from '~/components/ui/button'
import { Card } from '~/components/ui/card'
import { Checkbox } from '~/components/ui/checkbox'
import { Input } from '~/components/ui/input'
import { Label } from '~/components/ui/label'
import { SelectGroup, SelectItem, SelectLabel } from '~/components/ui/select'
import { Slider } from '~/components/ui/slider'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '~/components/ui/tabs'
import { Textarea } from '~/components/ui/textarea'
import { eventLabel, exampleAlgorithm, integerInRange, methodLabels, stagedAssistMethods } from '~/lib/playground'

const props = defineProps<{ language: SiteLanguage }>()
const english = computed(() => props.language === 'en')
const t = (zh: string, en: string) => english.value ? en : zh
const title = 'Cubegin SDK Playground'
const description = () => t('生成魔方打乱、尝试辅助求解，逐步回放每一个转动。', 'Generate scrambles, try assisted solving, and replay each move.')
useSiteSeo('playground', () => props.language, () => title, description)

type Mode = 'standard' | 'training' | 'assist'
interface Result {
  label: string
  algorithm: string
  detail?: string
  preview?: { event: string, algorithm: string, updateStandardInput?: boolean }
}

const route = useRoute()
const router = useRouter()
const mounted = ref(false)
const mode = computed<Mode>(() => {
  if (!mounted.value) return 'standard'
  const value = router.currentRoute.value.query.mode
  return value === 'assist' || value === 'training' ? value : 'standard'
})
function changeMode(value: string | number) {
  if (value !== mode.value && ['standard', 'training', 'assist'].includes(String(value))) {
    void writeAddress(stateQuery(value as Mode, includeLiveReplay()), true)
  }
}
const ready = ref(false)
const busy = ref(false)
const controlsDisabled = computed(() => !ready.value || busy.value)
const error = ref('')
const copied = ref('')
const sdkVersion = ref('')
const resultPanel = ref<HTMLElement>()
const results = ref<Result[]>([])
const rawResult = shallowRef<unknown>()
let client: WorkerClient | undefined
let disposed = false

const events = shallowRef<EventInfo[]>([])
const event = ref('333')
const algorithm = ref(exampleAlgorithm('333'))
const eventSeed = ref<number | string>('')
const blindCount = ref<number | string>(3)
const canSolve = computed(() => events.value.find(item => item.id === event.value)?.full_solver ?? false)

const trainingFilter = ref('all')
const trainingType = ref('333.pll')
const trainingSeed = ref<number | string>('')
const trainingCatalog = shallowRef<Record<string, Record<string, unknown>>>({})
const trainingTypes = computed(() => Object.entries(trainingCatalog.value).filter(([, item]) => item.kind !== 'official'))
const trainingEvents = computed(() => [...new Set(trainingTypes.value.map(([, item]) => String(item.baseEventId)))])
const trainingGroups = computed(() => {
  const groups = new Map<string, string[]>()
  for (const [id, item] of trainingTypes.value) {
    const baseEvent = String(item.baseEventId)
    if (trainingFilter.value !== 'all' && trainingFilter.value !== baseEvent) continue
    const group = `${eventLabel(baseEvent, english.value)} · ${item.categoryId}`
    const entries = groups.get(group) ?? []
    entries.push(id)
    groups.set(group, entries)
  }
  return groups
})
const trainingCases = shallowRef<{ id: string, natural_weight: number }[]>([])
const selectedCases = ref<string[]>([])
const natural = ref(false)
const bottomColor = ref<keyof typeof colors | 'default'>('default')
const frontColor = ref<keyof typeof colors | 'auto'>('auto')
const supportsOrientation = computed(() => Boolean(trainingCatalog.value[trainingType.value]?.orientationTarget))
const colors = {
  white: ['白', 'White'], yellow: ['黄', 'Yellow'], red: ['红', 'Red'],
  orange: ['橙', 'Orange'], green: ['绿', 'Green'], blue: ['蓝', 'Blue'],
} as const

const methods = shallowRef<[string, string][]>([])
const methodGroups = computed(() => {
  const groups = new Map<string, string[]>()
  for (const [id, method] of methods.value) {
    const entries = groups.get(id) ?? []
    entries.push(method)
    groups.set(id, entries)
  }
  return groups
})
const assistMethod = ref('cross')
const assistAlgorithm = ref('R U F')
const assistTargets = ref('')
const assistDepth = ref<number | string>('')
const assistCount = ref<number | string>(1)
const methodEvent = computed(() => methods.value.find(([, method]) => method === assistMethod.value)?.[0] ?? '333')
const stagedAssist = computed(() => stagedAssistMethods.has(assistMethod.value))

const playback = usePlaygroundPlayback(reportError)
const { preview, frame, drawnStep, position, duration, playing, speed, hasCameraOffset } = playback
let orbitDrag: { pointerId: number, x: number, y: number } | undefined

function startOrbit(event: PointerEvent) {
  if (!preview.value || busy.value || event.pointerType !== 'mouse' || event.button !== 0) return
  const surface = event.currentTarget as HTMLElement
  surface.setPointerCapture(event.pointerId)
  orbitDrag = { pointerId: event.pointerId, x: event.clientX, y: event.clientY }
}

function moveOrbit(event: PointerEvent) {
  if (!orbitDrag || orbitDrag.pointerId !== event.pointerId || !client) return
  if (!busy.value) playback.rotateCamera(client.engine, event.clientX - orbitDrag.x, event.clientY - orbitDrag.y)
  orbitDrag.x = event.clientX
  orbitDrag.y = event.clientY
}

function endOrbit(event: PointerEvent) {
  if (orbitDrag?.pointerId === event.pointerId) orbitDrag = undefined
}
const netSvg = computed(() => preview.value?.snapshot.svg.replace(/<svg\b[^>]*>/, tag => {
  if (/\bviewBox=/.test(tag)) return tag
  const width = Number(tag.match(/\bwidth="([\d.]+)"/)?.[1])
  const height = Number(tag.match(/\bheight="([\d.]+)"/)?.[1])
  return width > 0 && height > 0 ? tag.replace(/>$/, ` viewBox="0 0 ${width} ${height}">`) : tag
}) ?? '')
const seekValue = computed(() => [duration.value ? Math.round(position.value * 1000 / duration.value) : 0])
const playbackDisabled = computed(() => !duration.value || busy.value)
const caseSummary = computed(() => selectedCases.value.length
  ? t(`已选 ${selectedCases.value.length} 项`, `${selectedCases.value.length} selected`)
  : trainingCases.value.length
    ? t('全部案例', 'All cases')
    : t('无需选择案例', 'No cases to select'))

function seekPlayback(value?: number[]) {
  const target = value?.[0]
  if (target !== undefined && client && !playbackDisabled.value) {
    playback.seek(client.engine, target * duration.value / 1000)
  }
}
const debugOutput = computed(() => JSON.stringify({
  sdkVersion: sdkVersion.value,
  result: rawResult.value,
  preview: preview.value && {
    event: preview.value.event, algorithm: preview.value.algorithm, state: preview.value.snapshot.state,
  },
}, null, 2))

function reportError(failure: unknown) {
  if (!disposed) error.value = failure instanceof Error ? failure.message : String(failure)
}

async function run(action: (engine: AsyncEngine) => Promise<void>, reveal = false) {
  if (!client || busy.value) return
  busy.value = true
  error.value = ''
  copied.value = ''
  playback.pause()
  try {
    await action(client.engine)
    if (reveal && !disposed && matchMedia('(max-width: 800px)').matches) {
      await nextTick()
      resultPanel.value?.scrollIntoView({ block: 'start' })
    }
  } catch (failure) {
    reportError(failure)
  } finally {
    busy.value = false
  }
}

function fieldNumber(value: string | number, min: number, max: number, label: string) {
  try {
    return integerInRange(value, min, max)
  } catch {
    throw new Error(t(`${label}须为 ${min}–${max} 的整数。`, `${label} must be an integer from ${min} to ${max}.`))
  }
}

function seed(value: string | number) {
  return value === '' ? crypto.getRandomValues(new Uint32Array(1))[0]! : fieldNumber(value, 0, 0xffffffff, t('种子', 'Seed'))
}

function updateResults(items: Result[], raw: unknown) {
  results.value = items
  rawResult.value = raw
}

function standardPreview(engine: AsyncEngine) {
  return playback.show(engine, event.value, algorithm.value, eventLabel(event.value, english.value))
}

function changeEvent() {
  algorithm.value = exampleAlgorithm(event.value)
  void run(standardPreview)
}

function generateStandard() {
  void run(async engine => {
    const selected = event.value
    const selectedSeed = seed(eventSeed.value)
    const generated = selected === '333mbld'
      ? await engine.generateMultiBlind(selectedSeed, fieldNumber(blindCount.value, 2, 100, t('魔方数量', 'Puzzle count')))
      : [await engine.generateEvent(selected, selectedSeed)]
    const first = generated[0]
    if (!first) throw new Error(t('没有生成打乱。', 'No scramble was generated.'))
    const label = eventLabel(selected, english.value)
    await playback.show(engine, selected, first.algorithm, label)
    algorithm.value = first.algorithm
    updateResults(generated.map((item, index) => ({
      label: generated.length === 1 ? label : t(`第 ${index + 1} 个魔方`, `Puzzle ${index + 1}`),
      algorithm: item.algorithm,
      detail: t(`种子 ${item.seed}`, `Seed ${item.seed}`),
      preview: generated.length > 1 ? { event: selected, algorithm: item.algorithm, updateStandardInput: true } : undefined,
    })), generated)
  }, true)
}

function transformStandard(operation: 'solve' | 'inverse') {
  void run(async engine => {
    const formula = algorithm.value
    const output = await (operation === 'solve' ? engine.solveEvent(event.value, formula) : engine.inverseEvent(event.value, formula))
    const label = operation === 'solve' ? t('还原公式', 'Solution') : t('逆公式', 'Inverse')
    if (operation === 'solve') {
      const composed = [formula, output].filter(Boolean).join(' ')
      await playback.show(engine, event.value, composed, label)
      algorithm.value = composed
    }
    updateResults([{ label, algorithm: output }], { operation, input: formula, output })
  }, true)
}

async function loadTrainingCases(engine: AsyncEngine) {
  trainingCases.value = []
  selectedCases.value = []
  trainingCases.value = await engine.trainingCases(trainingType.value)
}

function changeTrainingFilter() {
  const first = trainingGroups.value.values().next().value?.[0]
  if (!first) return
  trainingType.value = first
  void run(loadTrainingCases)
}

function generateTraining() {
  void run(async engine => {
    const options: TrainingOptions = {}
    if (selectedCases.value.length) options.enabled_case_ids = [...selectedCases.value]
    if (trainingCases.value.length) options.natural = natural.value
    if (supportsOrientation.value && bottomColor.value !== 'default') {
      options.orientation = { bottomColor: bottomColor.value }
      if (frontColor.value !== 'auto') options.orientation.frontColor = frontColor.value
    }
    const generated = await engine.generateTraining(trainingType.value, seed(trainingSeed.value), options)
    const label = t('训练打乱', 'Training scramble')
    await playback.show(engine, generated.event_id, generated.algorithm, generated.scramble_type_id)
    const detail = [generated.scramble_type_id, t(`种子 ${generated.seed}`, `Seed ${generated.seed}`)]
    if (generated.case_id) detail.push(t(`案例 ${generated.case_id}`, `Case ${generated.case_id}`))
    if (generated.orientation) {
      const { bottomColor, frontColor } = generated.orientation
      detail.push(t(`底面 ${bottomColor} / 正面 ${frontColor}`, `Bottom ${bottomColor} / front ${frontColor}`))
    }
    updateResults([{ label, algorithm: generated.algorithm, detail: detail.join(' · ') }], generated)
  }, true)
}

function changeAssistMethod() {
  assistAlgorithm.value = ['333', '222'].includes(methodEvent.value) ? 'R U F' : exampleAlgorithm(methodEvent.value)
  assistTargets.value = ''
}

function solveAssist() {
  void run(async engine => {
    const options: AssistOptions = {}
    if (assistDepth.value !== '') options.max_depth = fieldNumber(assistDepth.value, 0, 30, t('最大深度', 'Maximum depth'))
    const targets = assistTargets.value.split(/[,，]/).map(target => target.trim()).filter(Boolean)
    if (targets.length) options.targets = targets
    if (assistMethod.value.startsWith('222-')) {
      options.max_solutions_per_target = fieldNumber(assistCount.value, 1, 64, t('每个目标的解数', 'Solutions per target'))
    }
    const formula = assistAlgorithm.value
    const found = await engine.solveAssist(methodEvent.value, [assistMethod.value], formula, options)
    let prior = formula
    const items = found.flatMap(result => result.solutions).map(solution => {
      const moves = [solution.setupRotation, solution.solution].filter(Boolean).join(' ')
      const composed = [stagedAssist.value ? prior : formula, moves].filter(Boolean).join(' ')
      if (stagedAssist.value) prior = composed
      return {
        label: solution.targetLabel,
        algorithm: moves,
        detail: t(`深度 ${solution.depth} · FTM ${solution.metric.ftm} · QTM ${solution.metric.qtm}`,
          `Depth ${solution.depth} · FTM ${solution.metric.ftm} · QTM ${solution.metric.qtm}`),
        preview: { event: methodEvent.value, algorithm: composed },
      }
    })
    const first = items[0]
    if (first) await playback.show(engine, first.preview.event, first.preview.algorithm, first.label)
    updateResults(items.length ? items : [{ label: t('未找到解', 'No solution found'), algorithm: '' }], found)
  }, true)
}

function showResult(result: Result) {
  const selected = result.preview
  if (!selected) return
  void run(async engine => {
    await playback.show(engine, selected.event, selected.algorithm, result.label)
    if (selected.updateStandardInput && selected.event === event.value && mode.value === 'standard') algorithm.value = selected.algorithm
  })
}

async function copyResult(result: Result, index: number) {
  try {
    await navigator.clipboard.writeText(result.algorithm)
    copied.value = String(index)
  } catch {
    reportError(new Error(t('无法复制，请选中公式手动复制。', 'Could not copy. Select the algorithm to copy it manually.')))
  }
}

function configurationQuery(activeMode: Mode) {
  const query = new URLSearchParams({ mode: activeMode })
  function set(key: string, value: number | string, fallback: number | string = '') {
    if (value !== fallback) query.set(key, String(value))
  }
  if (activeMode === 'standard') {
    query.set('event', event.value)
    set('input', algorithm.value, exampleAlgorithm(event.value))
    set('seed', eventSeed.value)
    if (event.value === '333mbld') set('count', blindCount.value, 3)
  } else if (activeMode === 'training') {
    query.set('type', trainingType.value)
    set('filter', trainingFilter.value, 'all')
    for (const id of selectedCases.value) query.append('case', id)
    if (natural.value) query.set('natural', '1')
    if (supportsOrientation.value) {
      set('bottom', bottomColor.value, 'default')
      set('front', frontColor.value, 'auto')
    }
    set('seed', trainingSeed.value)
  } else {
    query.set('method', assistMethod.value)
    query.set('input', assistAlgorithm.value)
    set('targets', assistTargets.value)
    set('depth', assistDepth.value)
    if (assistMethod.value.startsWith('222-')) set('count', assistCount.value, 1)
  }
  return query
}

function stateQuery(activeMode: Mode, includeReplay: boolean) {
  const query = configurationQuery(activeMode)
  if (includeReplay && preview.value) {
    if (activeMode === 'standard' && event.value !== preview.value.event) query.set('puzzle', event.value)
    if (activeMode === 'standard') {
      if (algorithm.value === preview.value.algorithm) query.delete('input')
      else query.set('input', algorithm.value)
    }
    query.set('event', preview.value.event)
    query.set('alg', preview.value.algorithm)
    query.set('step', String(drawnStep.value))
    if (speed.value !== 1) query.set('speed', String(speed.value))
  }
  return query
}

function includeLiveReplay() {
  const current = preview.value
  return !!current && (speed.value !== 1 || drawnStep.value > 0 || current.event !== '333' ||
    current.algorithm !== exampleAlgorithm('333') || algorithm.value !== current.algorithm)
}

async function copyLink(kind: 'config' | 'replay') {
  const query = stateQuery(mode.value, kind === 'replay')
  const url = new URL(window.location.href)
  url.search = query.toString()
  url.hash = ''
  try {
    await navigator.clipboard.writeText(url.href)
    copied.value = kind
  } catch {
    reportError(new Error(t('无法复制链接。', 'Could not copy the link.')))
  }
}

async function restoreQuery(engine: AsyncEngine, query: URLSearchParams) {
  const rate = Number(query.get('speed'))
  speed.value = [0.5, 1, 2].includes(rate) ? rate : 1
  updateResults([], undefined)
  const validEvent = (id: string | null) => events.value.some(item => item.id === id)
  const eventId = query.get('event')
  if (eventId !== null && !validEvent(eventId)) throw new Error(t('链接中的项目无效。', 'Unknown puzzle in link.'))
  const input = query.get('input')
  if (mode.value === 'standard') {
    const puzzle = query.get('puzzle') ?? eventId ?? '333'
    if (!validEvent(puzzle)) throw new Error(t('链接中的项目无效。', 'Unknown puzzle in link.'))
    event.value = puzzle
    algorithm.value = input ?? query.get('alg') ?? exampleAlgorithm(puzzle)
    eventSeed.value = query.get('seed') ?? ''
    blindCount.value = query.get('count') ?? 3
    if (!query.has('alg')) await standardPreview(engine)
  } else if (mode.value === 'training') {
    const type = query.get('type') ?? '333.pll'
    if (!trainingTypes.value.some(([id]) => id === type)) throw new Error(t('链接中的训练类型无效。', 'Unknown training type in link.'))
    trainingType.value = type
    const filter = query.get('filter')
    trainingFilter.value = filter && filter === trainingCatalog.value[type]?.baseEventId ? filter : 'all'
    await loadTrainingCases(engine)
    const cases = new Set(query.getAll('case'))
    selectedCases.value = trainingCases.value.filter(item => cases.has(item.id)).map(item => item.id)
    natural.value = query.get('natural') === '1'
    const bottom = query.get('bottom') as keyof typeof colors
    const front = query.get('front') as keyof typeof colors
    bottomColor.value = Object.hasOwn(colors, bottom) ? bottom : 'default'
    frontColor.value = Object.hasOwn(colors, front) ? front : 'auto'
    trainingSeed.value = query.get('seed') ?? ''
  } else {
    const method = query.get('method') ?? 'cross'
    if (!methods.value.some(([, id]) => id === method)) throw new Error(t('链接中的辅助方法无效。', 'Unknown assist method in link.'))
    assistMethod.value = method
    changeAssistMethod()
    assistAlgorithm.value = input ?? assistAlgorithm.value
    assistTargets.value = query.get('targets') ?? ''
    assistDepth.value = query.get('depth') ?? ''
    assistCount.value = query.get('count') ?? 1
  }
  const replay = query.get('alg')
  if (replay !== null) {
    const puzzle = eventId ?? '333'
    await playback.show(engine, puzzle, replay, eventLabel(puzzle, english.value))
    const steps = preview.value?.timeline.steps
    if (!steps) return
    const index = fieldNumber(query.get('step') ?? '0', 0, steps.length, t('回放步数', 'Replay step'))
    await playback.seek(engine, steps.slice(0, index).reduce((sum, step) => sum + step.durationMs, 0))
  }
}

// Tab switches create history entries. Edits and completed moves update the
// current entry without sending our own URL back through the SDK.
const liveQuery = computed(() => stateQuery(mode.value, includeLiveReplay()).toString())
let appliedPath: string | undefined
let lastState = ''
let writingPath: string | undefined
const restoring = ref(false)

async function writeAddress(query: URLSearchParams, push = false) {
  const target = { path: route.path, query: router.resolve('?' + query.toString()).query, hash: route.hash }
  const path = router.resolve(target).fullPath
  if (path === router.currentRoute.value.fullPath) return
  writingPath = path
  const failure = push ? await router.push(target) : await router.replace(target)
  if (failure && writingPath === path) writingPath = undefined
}

watch([() => router.currentRoute.value.fullPath, ready, busy, liveQuery, restoring], async () => {
  if (disposed || !ready.value || busy.value || restoring.value) return
  const path = router.currentRoute.value.fullPath
  if (router.currentRoute.value.path !== route.path) return
  if (appliedPath !== path) {
    const initial = appliedPath === undefined
    appliedPath = path
    if (path === writingPath) {
      writingPath = undefined
    } else {
      const query = new URL(window.location.href).searchParams
      restoring.value = true
      try {
        if (!initial || [...query.keys()].some(key => key !== 'mode')) {
          await run(engine => restoreQuery(engine, query))
        }
      } finally {
        lastState = liveQuery.value
        restoring.value = false
      }
      return
    }
  }
  if (lastState !== liveQuery.value) {
    lastState = liveQuery.value
    await writeAddress(new URLSearchParams(lastState))
  }
})

async function initialize() {
  if (busy.value || ready.value) return
  busy.value = true
  error.value = ''
  try {
    const { createWorkerClient } = await import('cubegin/worker')
    if (disposed) return
    client = createWorkerClient()
    const engine = client.engine
    const [eventList, types, assistList, version] = await Promise.all([
      engine.eventCatalog(), engine.typeCatalog(), engine.assistMethods(), engine.version(),
    ])
    if (disposed) return
    events.value = eventList
    trainingCatalog.value = types
    methods.value = assistList
    sdkVersion.value = version
    await Promise.all([loadTrainingCases(engine), standardPreview(engine)])
    if (!disposed) ready.value = true
  } catch (failure) {
    client?.dispose()
    client = undefined
    reportError(failure)
  } finally {
    busy.value = false
  }
}

onMounted(() => {
  mounted.value = true
  void initialize()
})
onBeforeUnmount(() => {
  disposed = true
  client?.dispose()
})
</script>

<template>
  <main class="playground">
    <div class="playground-heading">
      <h1>{{ title }}</h1>
      <span v-if="sdkVersion" class="sdk-version">v{{ sdkVersion }}</span>
    </div>

    <div class="workspace">
      <Card class="controls panel gap-0" role="region" :aria-label="t('操作', 'Controls')">
        <Tabs :model-value="mode" @update:model-value="changeMode" class="gap-0">
          <TabsList class="grid h-auto w-full grid-cols-3 gap-1 p-1" :aria-label="t('操作类型', 'Operation')">
            <TabsTrigger value="standard" class="h-auto min-w-0 px-1 py-2.5 text-xs sm:text-sm" :disabled="busy && ready">{{ t('标准打乱', 'Scramble') }}</TabsTrigger>
            <TabsTrigger value="training" class="h-auto min-w-0 px-1 py-2.5 text-xs sm:text-sm" :disabled="busy && ready">{{ t('训练打乱', 'Training') }}</TabsTrigger>
            <TabsTrigger value="assist" class="h-auto min-w-0 px-1 py-2.5 text-xs sm:text-sm" :disabled="busy && ready">{{ t('辅助求解', 'Solve assist') }}</TabsTrigger>
          </TabsList>

          <TabsContent value="standard" class="mode-content">
            <fieldset :disabled="controlsDisabled">
              <PlaygroundSelect
                id="event" v-model="event" :label="t('标准项目', 'Puzzle')" :disabled="controlsDisabled"
                :summary="eventLabel(event, english)" @update:model-value="changeEvent"
              >
                <SelectItem v-for="item in events" :key="item.id" :value="item.id" :data-option="item.id">
                  {{ eventLabel(item.id, english) }}
                </SelectItem>
              </PlaygroundSelect>
              <div class="field">
                <Label for="event-algorithm">{{ t('项目公式', 'Algorithm') }}</Label>
                <Textarea class="min-h-20 resize-y bg-background font-mono" id="event-algorithm" v-model="algorithm" rows="3" spellcheck="false" />
              </div>
              <PlaygroundDisclosure class="options" :label="t('高级选项', 'Advanced options')" :disabled="controlsDisabled">
                <div class="option-fields">
                  <div class="field">
                    <Label for="event-seed">{{ t('随机种子', 'Seed') }}</Label>
                    <Input id="event-seed" v-model="eventSeed" type="number" min="0" max="4294967295" :placeholder="t('留空随机生成', 'Random when empty')" class="bg-background" />
                  </div>
                  <div v-if="event === '333mbld'" class="field">
                    <Label for="blind-count">{{ t('多盲魔方数量', 'Multi-blind puzzle count') }}</Label>
                    <Input id="blind-count" v-model="blindCount" type="number" min="2" max="100" class="bg-background" />
                  </div>
                </div>
              </PlaygroundDisclosure>
              <Button id="event-generate" class="primary-action" @click="generateStandard">{{ t('生成项目打乱', 'Generate scramble') }}</Button>
              <div class="secondary-actions">
                <Button id="event-apply" variant="secondary" @click="run(standardPreview, true)">{{ t('查看图与动画', 'Preview algorithm') }}</Button>
                <Button id="event-solve" variant="secondary" :disabled="!canSolve" @click="transformStandard('solve')">{{ t('求解并回放', 'Solve and replay') }}</Button>
                <Button id="event-inverse" variant="ghost" @click="transformStandard('inverse')">{{ t('逆公式', 'Invert') }}</Button>
              </div>
              <p v-if="ready && !canSolve" class="field-hint">{{ t('该项目支持打乱和回放，暂无完整求解。', 'Scrambling and replay are available for this puzzle. Full solving is unavailable.') }}</p>
            </fieldset>
          </TabsContent>

          <TabsContent value="training" class="mode-content">
            <fieldset :disabled="controlsDisabled">
              <PlaygroundSelect
                id="training-event" v-model="trainingFilter" :label="t('训练项目筛选', 'Filter by puzzle')" :disabled="controlsDisabled"
                :summary="trainingFilter === 'all' ? t('全部项目', 'All puzzles') : eventLabel(trainingFilter, english)"
                @update:model-value="changeTrainingFilter"
              >
                <SelectItem value="all">{{ t('全部项目', 'All puzzles') }}</SelectItem>
                <SelectItem v-for="id in trainingEvents" :key="id" :value="id" :data-option="id">{{ eventLabel(id, english) }}</SelectItem>
              </PlaygroundSelect>
              <PlaygroundSelect
                id="training-type" v-model="trainingType" :label="t('训练类型', 'Training type')" :disabled="controlsDisabled"
                :summary="trainingType" @update:model-value="run(loadTrainingCases)"
              >
                <SelectGroup v-for="[group, items] in trainingGroups" :key="group">
                  <SelectLabel>{{ group }}</SelectLabel>
                  <SelectItem v-for="id in items" :key="id" :value="id" :data-option="id">{{ id }}</SelectItem>
                </SelectGroup>
              </PlaygroundSelect>
              <div class="field">
                <PlaygroundSelect
                  id="training-cases" v-model="selectedCases" :label="t('限定案例（可多选）', 'Cases (multi-select)')"
                  :disabled="controlsDisabled || !trainingCases.length" :summary="caseSummary" described-by="case-status"
                >
                  <SelectItem v-for="item in trainingCases" :key="item.id" :value="item.id" :data-option="item.id">
                    {{ item.id }} · {{ t('权重', 'Weight') }} {{ item.natural_weight }}
                  </SelectItem>
                </PlaygroundSelect>
                <div class="case-help">
                  <p id="case-status" class="field-hint">{{ trainingCases.length ? t('不选则使用全部案例。', 'Leave empty to use all cases.') : t('此类型无需限定案例。', 'This type generates without cases.') }}</p>
                  <Button v-if="selectedCases.length" id="training-clear-cases" variant="ghost" size="xs" type="button" @click="selectedCases = []">
                    {{ t('清除', 'Clear') }}
                  </Button>
                </div>
              </div>
              <PlaygroundDisclosure class="options" :label="t('高级选项', 'Advanced options')" :disabled="controlsDisabled">
                <div class="option-fields">
                  <div class="field">
                    <Label for="training-seed">{{ t('训练随机种子', 'Training seed') }}</Label>
                    <Input id="training-seed" v-model="trainingSeed" type="number" min="0" max="4294967295" :placeholder="t('留空随机生成', 'Random when empty')" class="bg-background" />
                  </div>
                  <div v-if="trainingCases.length" class="check-field">
                    <Checkbox id="natural" v-model="natural" :disabled="controlsDisabled" />
                    <Label for="natural">{{ t('按自然权重选择案例', 'Use natural case weights') }}</Label>
                  </div>
                  <template v-if="supportsOrientation">
                    <PlaygroundSelect
                      id="bottom-color" v-model="bottomColor" :label="t('底面颜色', 'Bottom color')" :disabled="controlsDisabled"
                      :summary="bottomColor === 'default' ? t('默认朝向', 'Default orientation') : colors[bottomColor]?.[english ? 1 : 0]"
                    >
                      <SelectItem value="default">{{ t('默认朝向', 'Default orientation') }}</SelectItem>
                      <SelectItem v-for="(name, color) in colors" :key="color" :value="color" :data-option="color">{{ name[english ? 1 : 0] }}</SelectItem>
                    </PlaygroundSelect>
                    <PlaygroundSelect
                      id="front-color" v-model="frontColor" :label="t('正面颜色', 'Front color')"
                      :disabled="controlsDisabled || bottomColor === 'default'"
                      :summary="frontColor === 'auto' ? t('自动选择相邻颜色', 'Choose adjacent color automatically') : colors[frontColor]?.[english ? 1 : 0]"
                    >
                      <SelectItem value="auto">{{ t('自动选择相邻颜色', 'Choose adjacent color automatically') }}</SelectItem>
                      <SelectItem v-for="(name, color) in colors" :key="color" :value="color" :data-option="color">{{ name[english ? 1 : 0] }}</SelectItem>
                    </PlaygroundSelect>
                  </template>
                </div>
              </PlaygroundDisclosure>
              <Button id="training-generate" class="primary-action" @click="generateTraining">{{ t('生成训练打乱', 'Generate training scramble') }}</Button>
            </fieldset>
          </TabsContent>

          <TabsContent value="assist" class="mode-content">
            <fieldset :disabled="controlsDisabled">
              <PlaygroundSelect
                id="assist-method" v-model="assistMethod" :label="t('求解方法', 'Method')" :disabled="controlsDisabled"
                :summary="methodLabels[assistMethod]?.[english ? 1 : 0] ?? assistMethod" @update:model-value="changeAssistMethod"
              >
                <SelectGroup v-for="[id, items] in methodGroups" :key="id">
                  <SelectLabel>{{ eventLabel(id, english) }}</SelectLabel>
                  <SelectItem v-for="method in items" :key="method" :value="method" :data-option="method">
                    {{ methodLabels[method]?.[english ? 1 : 0] ?? method }}
                  </SelectItem>
                </SelectGroup>
              </PlaygroundSelect>
              <div class="field">
                <Label for="assist-algorithm">{{ t('待求解打乱', 'Scramble to solve') }}</Label>
                <Textarea class="min-h-20 resize-y bg-background font-mono" id="assist-algorithm" v-model="assistAlgorithm" rows="3" spellcheck="false" />
              </div>
              <PlaygroundDisclosure class="options" :label="t('高级选项', 'Advanced options')" :disabled="controlsDisabled">
                <div class="option-fields">
                  <div class="field">
                    <Label for="assist-targets">{{ t('限定目标（可选）', 'Targets (optional)') }}</Label>
                    <Input id="assist-targets" v-model="assistTargets" :placeholder="t('例如 D, U，以逗号分隔', 'For example D, U')" class="bg-background" />
                  </div>
                  <div class="field">
                    <Label for="assist-depth">{{ t('最大深度（可选）', 'Maximum depth (optional)') }}</Label>
                    <Input id="assist-depth" v-model="assistDepth" type="number" min="0" max="30" :placeholder="t('使用方法默认值', 'Method default')" class="bg-background" />
                  </div>
                  <div v-if="assistMethod.startsWith('222-')" class="field">
                    <Label for="assist-count">{{ t('每个目标最多解数', 'Solutions per target') }}</Label>
                    <Input id="assist-count" v-model="assistCount" type="number" min="1" max="64" class="bg-background" />
                  </div>
                </div>
              </PlaygroundDisclosure>
              <Button id="assist-run" class="primary-action" @click="solveAssist">{{ t('运行辅助求解', 'Run solve assist') }}</Button>
              <p v-if="stagedAssist" class="field-hint">{{ t('按顺序执行各阶段，预览会包含此前的步骤。', 'Run stages in order. Each preview includes prior stages.') }}</p>
            </fieldset>
          </TabsContent>
        </Tabs>
        <Button variant="ghost" size="sm" class="self-start" :disabled="controlsDisabled" @click="copyLink('config')">
          <Check v-if="copied === 'config'" /><Link2 v-else />
          {{ copied === 'config' ? t('已复制配置链接', 'Configuration link copied') : t('复制配置链接', 'Copy configuration link') }}
        </Button>
        <div class="operation-status">
          <p v-if="busy" role="status">{{ ready ? t('正在处理…', 'Working…') : t('正在加载 SDK…', 'Loading SDK…') }}</p>
          <p v-if="error" id="workbench-error" role="alert">{{ error }}</p>
          <Button v-if="error && !ready" variant="secondary" size="sm" @click="initialize">{{ t('重试', 'Retry') }}</Button>
        </div>
      </Card>

      <section ref="resultPanel" class="result-panel" aria-labelledby="result-title">
        <Card class="panel result-card gap-0">
          <div class="result-heading">
            <h2 id="result-title">{{ t('结果与回放', 'Results & replay') }}</h2>
            <p v-if="preview" id="preview-source">
              {{ preview.label }} · {{ preview.snapshot.solved ? t('已还原', 'Solved') : t('未还原', 'Scrambled') }}
            </p>
          </div>
          <div id="playground-output" class="results" aria-live="polite">
            <article v-for="(result, index) in results" :key="index" class="result-row">
              <div class="result-summary">
                <strong>{{ result.label }}</strong>
                <span v-if="result.detail">{{ result.detail }}</span>
              </div>
              <code v-if="result.algorithm">{{ result.algorithm }}</code>
              <div v-if="result.algorithm || result.preview" class="result-actions">
                <Button v-if="result.preview" variant="ghost" size="sm" :disabled="busy" @click="showResult(result)">
                  {{ t('预览结果', 'Preview') }}
                </Button>
                <Button
                  v-if="result.algorithm" variant="ghost" size="icon" class="size-9"
                  :aria-label="copied === String(index) ? t('已复制', 'Copied') : t('复制公式', 'Copy algorithm')"
                  :title="copied === String(index) ? t('已复制', 'Copied') : t('复制公式', 'Copy algorithm')"
                  @click="copyResult(result, index)"
                >
                  <Check v-if="copied === String(index)" aria-hidden="true" />
                  <Copy v-else aria-hidden="true" />
                </Button>
              </div>
            </article>
          </div>
          <div class="preview-stage">
            <figure>
              <figcaption class="animation-caption">
                {{ t('动画', 'Animation') }}
                <Button
                  v-if="hasCameraOffset" variant="ghost" size="icon-xs" class="camera-reset" :disabled="busy"
                  :aria-label="t('重置视角', 'Reset view')" :title="t('重置视角', 'Reset view')"
                  @click="client && playback.resetCamera(client.engine)"
                >
                  <RotateCcw aria-hidden="true" />
                </Button>
              </figcaption>
              <div
                id="player-frame" class="preview-image" :class="{ 'orbit-surface': preview && !busy }"
                :title="t('按住鼠标左键拖动可旋转视角', 'Drag with the left mouse button to rotate the view')"
                @pointerdown="startOrbit" @pointermove="moveOrbit" @lostpointercapture="endOrbit"
                v-html="frame"
              />
            </figure>
            <figure>
              <figcaption>{{ t('最终状态展开图', 'Final state net') }}</figcaption>
              <div id="event-net" class="preview-image net" v-html="netSvg" />
            </figure>
          </div>
          <fieldset class="playback" :disabled="playbackDisabled">
            <div class="seek-row">
              <Slider
                id="seek" :label="t('动画进度', 'Animation progress')" :model-value="seekValue" :max="1000"
                :disabled="playbackDisabled" class="h-7 min-w-0 flex-1" @update:model-value="seekPlayback"
              />
              <span id="event-status">{{ drawnStep }}/{{ preview?.timeline.steps.length ?? 0 }}</span>
            </div>
            <div class="playback-bar">
              <Button id="play" variant="secondary" size="sm" @click="client && playback.toggle(client.engine)">
                <Pause v-if="playing" aria-hidden="true" />
                <Play v-else aria-hidden="true" />
                {{ playing ? t('暂停', 'Pause') : t('播放', 'Play') }}
              </Button>
              <Button id="restart" variant="ghost" size="icon" class="size-9" :aria-label="t('回到起点', 'Restart')" :title="t('回到起点', 'Restart')" @click="client && playback.seek(client.engine, 0)">
                <RotateCcw aria-hidden="true" />
              </Button>
              <Button variant="ghost" size="icon" class="size-9" :aria-label="t('上一步', 'Previous move')" :title="t('上一步', 'Previous move')" @click="client && playback.step(client.engine, -1)">
                <Rewind aria-hidden="true" />
              </Button>
              <Button variant="ghost" size="icon" class="size-9" :aria-label="t('下一步', 'Next move')" :title="t('下一步', 'Next move')" @click="client && playback.step(client.engine, 1)">
                <FastForward aria-hidden="true" />
              </Button>
              <span id="move-label">{{ preview?.timeline.steps[drawnStep]?.notation }}</span>
              <PlaygroundSelect
                id="speed" v-model="speed" :label="t('播放速度', 'Playback speed')" :disabled="playbackDisabled"
                :summary="`${speed}×`" compact class="ms-auto"
              >
                <SelectItem v-for="rate in [0.5, 1, 2]" :key="rate" :value="rate">{{ rate }}×</SelectItem>
              </PlaygroundSelect>
            </div>
          </fieldset>
          <Button variant="ghost" size="sm" class="self-start" :disabled="controlsDisabled || !preview" @click="copyLink('replay')">
            <Check v-if="copied === 'replay'" /><Link2 v-else />
            {{ copied === 'replay' ? t('已复制回放链接', 'Replay link copied') : t('复制回放链接', 'Copy replay link') }}
          </Button>
        </Card>
      </section>
    </div>

    <PlaygroundDisclosure class="debug" :label="t('调试信息', 'Debug information')" :disabled="!ready && !error">
      <pre>{{ debugOutput }}</pre>
      <PlaygroundBasicApi v-if="ready && client" :engine="client.engine" :language="language" />
    </PlaygroundDisclosure>
  </main>
</template>

<style scoped>
.playground {
  width: min(78rem, 100% - 2 * clamp(.85rem, 4vw, 3rem));
  margin-inline: auto;
  padding-block: clamp(2rem, 5vw, 4rem) 3rem;
}

.playground-heading, .result-heading {
  display: flex;
  align-items: baseline;
  gap: .75rem 1.5rem;
  flex-wrap: wrap;
}

.result-heading { justify-content: space-between; }
.playground-heading { gap: .25rem .75rem; margin-bottom: 1.5rem; }
.playground-heading h1 {
  font-size: clamp(1.75rem, 3.8vw, 2.75rem);
  line-height: 1.06;
  letter-spacing: -.055em;
  font-weight: 760;
}
.sdk-version { color: var(--muted-foreground); font-family: ui-monospace, monospace; font-size: .8rem; }
.workspace { display: grid; grid-template-columns: minmax(19rem, .75fr) minmax(0, 1.25fr); gap: 1.25rem; align-items: start; }
.panel {
  min-width: 0;
  background: color-mix(in srgb, var(--background) 87%, var(--secondary));
  border: 1px solid var(--border);
  border-radius: 1.2rem;
}
.controls { padding: 1rem; }
.mode-content { padding: 1rem .2rem .1rem; }
.mode-content fieldset, .option-fields {
  display: grid;
  min-width: 0;
  gap: 1rem;
}
.field { display: grid; gap: .4rem; min-width: 0; }
.check-field { display: flex; align-items: center; gap: .5rem; }
.field-hint { color: var(--muted-foreground); font-size: .8rem; font-weight: 450; }
.case-help, .secondary-actions { display: flex; flex-wrap: wrap; align-items: center; gap: .4rem .65rem; }
.options, .debug { border-top: 1px solid var(--border); }
.option-fields { padding: .15rem 0 .55rem; }
.primary-action { width: 100%; }
.secondary-actions { gap: .4rem; }
.secondary-actions button { padding-inline: .6rem; }
.operation-status { padding-inline: .2rem; font-size: .85rem; }
.operation-status p { margin-top: .75rem; }
.operation-status p[role="alert"] { color: var(--destructive); overflow-wrap: anywhere; }
.operation-status button { margin-top: .6rem; }
.result-panel { min-width: 0; scroll-margin-top: .75rem; }
.result-card { padding: clamp(.85rem, 2.5vw, 1.5rem); }
.result-heading h2 { font-size: 1.15rem; font-weight: 720; }
.result-heading p { color: var(--muted-foreground); font-size: .855rem; }
.results:not(:empty) { display: grid; gap: .45rem; margin-top: 1rem; max-height: 22rem; overflow: auto; }
.result-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: center;
  gap: .4rem .75rem;
  padding: .65rem .75rem;
  border-radius: .65rem;
  background: var(--secondary);
  font-size: .88rem;
}
.result-summary { display: flex; flex-wrap: wrap; align-items: baseline; column-gap: .55rem; }
.result-summary span { color: var(--muted-foreground); font-size: .78rem; }
.result-row code { grid-column: 1; overflow-wrap: anywhere; }
.result-actions { grid-column: 2; grid-row: 1 / span 2; display: flex; align-items: center; }
.preview-stage {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 1px;
  margin-top: 1rem;
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: .85rem;
  background: var(--border);
}
.preview-stage figure {
  display: flex;
  flex-direction: column;
  min-width: 0;
  padding: .85rem;
  background: color-mix(in srgb, var(--secondary) 58%, var(--background));
}
.preview-stage figcaption { color: var(--muted-foreground); font-size: .78rem; font-weight: 650; }
.animation-caption { position: relative; padding-inline-end: 2rem; }
.camera-reset { position: absolute; inset-inline-end: 0; top: 50%; translate: 0 -50%; }
.orbit-surface { cursor: grab; user-select: none; }
.orbit-surface:active { cursor: grabbing; }
.preview-image { display: grid; place-items: center; min-height: clamp(7.25rem, 21vw, 17rem); }
.preview-image :deep(svg) { width: 100%; height: auto; max-width: 17rem; max-height: 17rem; }
.preview-image.net :deep(svg) { max-width: 15rem; }
.playback { display: grid; gap: .4rem; margin-top: .85rem; min-width: 0; }
.seek-row, .playback-bar { display: flex; align-items: center; gap: .45rem; }
#event-status, #move-label { min-width: 3ch; color: var(--muted-foreground); font: .8rem ui-monospace, monospace; }
#event-status { min-width: 5ch; text-align: end; }
.debug { margin-top: 1.25rem; }
.debug pre {
  max-height: 17rem;
  overflow: auto;
  border-radius: .6rem;
  background: var(--secondary);
  padding: .9rem;
  font-size: .8rem;
}
@media (max-width: 800px) {
  .workspace { grid-template-columns: minmax(0, 1fr); }
}
@media (max-width: 420px) {
  .result-row { gap: .25rem; padding: .55rem; }
  .preview-stage figure { padding-inline: .5rem; }
  .playback-bar { gap: .2rem; }
}
</style>
