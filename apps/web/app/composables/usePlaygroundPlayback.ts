import type { CameraOffset, EventSnapshot, PlayerTimeline } from 'cubegin'
import type { AsyncEngine } from 'cubegin/worker'

interface PlaybackPreview {
  event: string
  algorithm: string
  label: string
  snapshot: EventSnapshot
  timeline: PlayerTimeline
}

function playbackPosition(time: number, timeline: PlayerTimeline) {
  let start = 0
  for (const [index, step] of timeline.steps.entries()) {
    const end = start + step.durationMs
    if (time < end) return { step: index, progress: (time - start) / step.durationMs }
    start = end
  }
  return { step: timeline.steps.length, progress: 0 }
}

export function usePlaygroundPlayback(onError: (error: unknown) => void) {
  const preview = shallowRef<PlaybackPreview>()
  const frame = ref('')
  const drawnStep = ref(0)
  const position = ref(0)
  const playing = ref(false)
  const speed = ref(1)
  const camera = shallowRef<CameraOffset>()
  const duration = computed(() => preview.value?.timeline.totalDurationMs ?? 0)
  const hasCameraOffset = computed(() => camera.value !== undefined)
  let animation = 0
  let revision = 0
  let drawing = false
  let pending: { time: number, engine: AsyncEngine } | undefined

  function pause() {
    playing.value = false
    if (animation) cancelAnimationFrame(animation)
    animation = 0
  }

  async function show(engine: AsyncEngine, event: string, algorithm: string, label: string) {
    pause()
    pending = undefined
    const requested = ++revision
    const nextCamera = preview.value?.event === event ? camera.value : undefined
    const [snapshot, timeline, svg] = await Promise.all([
      engine.evaluateEvent(event, algorithm),
      engine.playerTimeline(event, algorithm),
      engine.playerSvg(event, algorithm, 0, 0, nextCamera),
    ])
    if (requested !== revision) return
    preview.value = { event, algorithm, label, snapshot, timeline }
    camera.value = nextCamera
    frame.value = svg
    position.value = 0
    drawnStep.value = 0
  }

  async function draw(engine: AsyncEngine, time: number) {
    position.value = time
    pending = { engine, time }
    if (drawing) return
    drawing = true
    try {
      while (pending) {
        const request = pending
        pending = undefined
        const current = preview.value
        if (!current) continue
        const requested = revision
        const { step, progress } = playbackPosition(request.time, current.timeline)
        try {
          const svg = await request.engine.playerSvg(current.event, current.algorithm, step, progress, camera.value)
          if (requested === revision) {
            frame.value = svg
            drawnStep.value = step
          }
        } catch (error) {
          if (requested === revision) {
            pause()
            pending = undefined
            onError(error)
          }
        }
      }
    } finally {
      drawing = false
    }
  }

  function seek(engine: AsyncEngine, time: number) {
    pause()
    return draw(engine, time)
  }

  function rotateCamera(engine: AsyncEngine, dx: number, dy: number) {
    if (!preview.value || !(dx || dy)) return
    const rotationPerPixel = 0.009
    const fullTurn = 2 * Math.PI
    camera.value = {
      yaw: ((camera.value?.yaw ?? 0) - dx * rotationPerPixel) % fullTurn,
      pitch: ((camera.value?.pitch ?? 0) - dy * rotationPerPixel) % fullTurn,
    }
    void draw(engine, position.value)
  }

  function resetCamera(engine: AsyncEngine) {
    camera.value = undefined
    void draw(engine, position.value)
  }

  function step(engine: AsyncEngine, direction: -1 | 1) {
    const timeline = preview.value?.timeline
    if (!timeline) return
    const current = playbackPosition(position.value, timeline).step
    const next = Math.max(0, Math.min(timeline.steps.length, current + direction))
    const time = timeline.steps.slice(0, next).reduce((sum, move) => sum + move.durationMs, 0)
    seek(engine, time)
  }

  function toggle(engine: AsyncEngine) {
    if (playing.value) {
      pause()
      return
    }
    if (!duration.value) return
    if (position.value >= duration.value) position.value = 0
    playing.value = true
    // Use frame timestamps throughout. The first frame can precede the click's timestamp.
    let previous: number | undefined
    function tick(now: number) {
      if (!playing.value) return
      const elapsed = previous === undefined ? 0 : now - previous
      previous = now
      const time = Math.min(duration.value, position.value + elapsed * speed.value)
      void draw(engine, time)
      if (time < duration.value) animation = requestAnimationFrame(tick)
      else pause()
    }
    animation = requestAnimationFrame(tick)
  }

  onBeforeUnmount(() => {
    pause()
    pending = undefined
    revision++
  })

  return {
    preview, frame, drawnStep, position, duration, playing, speed, hasCameraOffset,
    show, pause, seek, step, toggle, rotateCamera, resetCamera,
  }
}
