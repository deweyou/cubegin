<script setup lang="ts">
import cubeginMark from '../../../ios/Design/LegacyIcons/brand/svg/cubegin-mark.svg?raw'
import cubeginWordmarkDark from '../../../ios/Design/LegacyIcons/brand/svg/cubegin-wordmark-dark.svg?url'
import cubeginWordmark from '../../../ios/Design/LegacyIcons/brand/svg/cubegin-wordmark.svg?url'
import darkStatisticsScreenshot from '~/assets/images/iphone-statistics-dark.jpg?url'
import lightStatisticsScreenshot from '~/assets/images/iphone-statistics-light.jpg?url'
import darkTimerScreenshot from '~/assets/images/iphone-timer-dark.jpg?url'
import lightTimerScreenshot from '~/assets/images/iphone-timer-light.jpg?url'
import { Button } from '~/components/ui/button'

const props = defineProps<{ language: 'zh-Hans' | 'en' }>()

const copy = {
  'zh-Hans': {
    title: '魔方速拧计时器',
    summary: ['为魔方速拧设计的计时器，', '支持专项训练、成绩统计和 iCloud 同步。'],
    capabilities: [
      { label: 'WCA 观察', tags: ['语音报时', '超时判罚'] },
      { label: '打乱与训练', tags: ['打乱公式', '打乱图', '辅助公式'] },
      { label: '成绩统计', tags: ['成绩分组', '平均成绩', '用时趋势'] },
      { label: 'iCloud 同步', tags: ['计时偏好', '语言与外观'] },
      { label: '支持设备', tags: ['iPhone', 'iPhone Duo', 'iPad'] },
    ],
    close: '关闭',
    timer: '计时页',
    statistics: '统计页',
    enlargeTimer: '放大计时页',
    enlargeStatistics: '放大统计页',
  },
  en: {
    title: 'Speedcubing timer',
    summary: ['A timer built for speedcubing, with targeted drills, solve statistics, and iCloud sync.'],
    capabilities: [
      { label: 'WCA inspection', tags: ['Voice alerts', 'Overtime penalties'] },
      { label: 'Scrambles & drills', tags: ['Scramble notation', 'Scramble diagrams', 'Formula hints'] },
      { label: 'Statistics', tags: ['Solve groups', 'Averages', 'Time trends'] },
      { label: 'iCloud sync', tags: ['Timer preferences', 'Language & appearance'] },
      { label: 'Devices', tags: ['iPhone', 'iPhone Duo', 'iPad'] },
    ],
    close: 'Close',
    timer: 'Timer',
    statistics: 'Statistics',
    enlargeTimer: 'Enlarge the timer screenshot',
    enlargeStatistics: 'Enlarge the statistics screenshot',
  },
}

const screenshotFiles = {
  timer: { light: lightTimerScreenshot, dark: darkTimerScreenshot },
  statistics: { light: lightStatisticsScreenshot, dark: darkStatisticsScreenshot },
}

type Screenshot = keyof typeof screenshotFiles

const content = computed(() => copy[props.language])
const dialog = useTemplateRef<HTMLDialogElement>('preview')
const selectedScreenshot = ref<Screenshot>('timer')
const themePreference = useThemePreference()
const darkScreenshotMedia = computed(() => {
  if (themePreference.value === 'dark') return 'all'
  if (themePreference.value === 'light') return 'not all'
  return '(prefers-color-scheme: dark)'
})

useSiteSeo(
  'home',
  () => props.language,
  () => `Cubegin | ${content.value.title}`,
  () => content.value.summary.join(''),
)

function showScreenshot(screenshot: Screenshot) {
  selectedScreenshot.value = screenshot
  dialog.value?.showModal()
}
</script>

<template>
  <main>
    <section class="hero" aria-labelledby="home-title">
      <div class="hero-copy">
        <h1 id="home-title" class="hero-logo">
          <span class="hero-mark" aria-hidden="true" v-html="cubeginMark"></span>
          <picture>
            <source :media="darkScreenshotMedia" :srcset="cubeginWordmarkDark">
            <img :src="cubeginWordmark" alt="cubegin" width="702" height="195">
          </picture>
        </h1>
        <p class="hero-summary">
          <span v-for="phrase in content.summary" :key="phrase">{{ phrase }}</span>
        </p>
        <dl class="capabilities">
          <div v-for="capability in content.capabilities" :key="capability.label" class="capability">
            <dt>{{ capability.label }}</dt>
            <dd>
              <span v-for="tag in capability.tags" :key="tag">{{ tag }}</span>
            </dd>
          </div>
        </dl>
      </div>
      <div class="showcase">
        <button type="button" class="screen statistics" :aria-label="content.enlargeStatistics" @click="showScreenshot('statistics')">
          <picture>
            <source :media="darkScreenshotMedia" :srcset="screenshotFiles.statistics.dark">
            <img :src="screenshotFiles.statistics.light" :alt="content.statistics" width="659" height="1434">
          </picture>
        </button>
        <button type="button" class="screen timer" :aria-label="content.enlargeTimer" @click="showScreenshot('timer')">
          <picture>
            <source :media="darkScreenshotMedia" :srcset="screenshotFiles.timer.dark">
            <img :src="screenshotFiles.timer.light" :alt="content.timer" width="659" height="1434" fetchpriority="high">
          </picture>
        </button>
      </div>
    </section>

    <dialog ref="preview" class="preview" aria-labelledby="preview-title">
      <div class="preview-header">
        <h2 id="preview-title">{{ content[selectedScreenshot] }}</h2>
        <form method="dialog">
          <Button type="submit" variant="ghost" autofocus>{{ content.close }}</Button>
        </form>
      </div>
      <picture>
        <source :media="darkScreenshotMedia" :srcset="screenshotFiles[selectedScreenshot].dark">
        <img :src="screenshotFiles[selectedScreenshot].light" :alt="content[selectedScreenshot]">
      </picture>
    </dialog>
  </main>
</template>

<style scoped>
.hero {
  --hero-height: calc(100dvh - var(--home-toolbar-height) - var(--home-footer-height));
  --glass-fill: light-dark(#ffffffad, #ffffff12);
  --glass-edge: light-dark(#ffffffd9, #ffffff24);
  --screen-shadow: light-dark(#233b5929, #0000006b);
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1.13fr);
  align-items: center;
  gap: clamp(.75rem, 4vw, 4rem);
  min-height: var(--hero-height);
  padding: clamp(1.25rem, 3dvh, 2.25rem) clamp(2.5rem, 8vw, 8.5rem);
}

.hero-logo {
  display: flex;
  align-items: center;
  gap: .12em;
  margin: 0;
  font-size: clamp(2.6rem, 6.1vw, 6rem);
}

.hero-mark, .hero-mark :deep(svg) { display: block; width: 1em; height: 1em; }
.hero-logo img { display: block; width: auto; height: .64em; }
.hero-mark :deep(rect:last-of-type) {
  transform-box: fill-box;
  transform-origin: center;
  transform: rotate(18deg);
}

@keyframes cubegin-turn {
  0% {
    transform: rotate(18deg);
    animation-timing-function: cubic-bezier(.16, .67, .27, 1);
  }
  22%, 100% { transform: rotate(378deg); }
}

.hero-summary {
  max-width: 30rem;
  margin: 1rem 0 0;
  font-size: clamp(1.125rem, 1.55vw, 1.375rem);
  font-weight: 500;
  line-height: 1.5;
  text-wrap: balance;
}

.hero-summary span { display: inline-block; max-width: 100%; }

.capabilities {
  display: grid;
  grid-template-columns: max-content minmax(0, 1fr);
  gap: .5625rem 1.125rem;
  max-width: 35rem;
  margin: 1.375rem 0 0;
  font-size: .875rem;
  line-height: 1.5;
}

.capability {
  display: grid;
  grid-column: 1 / -1;
  grid-template-columns: subgrid;
  align-items: start;
}

.capability dt {
  padding-block: .1875rem;
  color: var(--foreground);
  font-weight: 600;
}

.capability dd {
  display: flex;
  flex-wrap: wrap;
  gap: .25rem .375rem;
  min-width: 0;
  margin: 0;
}

.capability dd span {
  max-width: 100%;
  padding: .1875rem .5rem;
  border-radius: .375rem;
  background: color-mix(in srgb, var(--secondary) 75%, transparent);
  color: var(--muted-foreground);
  font-size: .8125rem;
  line-height: 1.6;
  overflow-wrap: anywhere;
}

.showcase {
  --shot-width: clamp(8rem, min(20.4vw, (var(--hero-height) - 5rem) / 2.7), 18.875rem);
  position: relative;
  width: min(100%, 36.875rem);
  height: calc(var(--shot-width) * 2.68);
  margin-inline: auto;
}

.screen {
  position: absolute;
  width: var(--shot-width);
  padding: .375rem;
  border: 1px solid var(--glass-edge);
  border-radius: clamp(.9375rem, 1.65vw, 1.625rem);
  background: var(--glass-fill);
  box-shadow: 0 1.0625rem 2.5rem var(--screen-shadow);
  cursor: zoom-in;
}

.screen:focus-visible {
  outline: 2px solid var(--ring);
  outline-offset: 3px;
}

.screen picture { display: block; border-radius: inherit; }
.screen img { display: block; width: 100%; height: auto; border-radius: inherit; }
.timer { z-index: 1; left: 2%; top: 1%; rotate: -8deg; }
.statistics { right: 2%; top: 13%; rotate: 8deg; }

@media (prefers-reduced-transparency: reduce) {
  .hero { --glass-fill: var(--background); }
}

@media (hover: hover) {
  .screen:hover { translate: 0 -.3125rem; }
}

@media (prefers-reduced-motion: no-preference) {
  .screen { transition: translate .16s ease-out; }
  .hero-mark :deep(rect:last-of-type) { animation: cubegin-turn 5s infinite; }
}

.preview {
  position: fixed;
  inset: 0;
  width: min(26.875rem, calc(100% - 1.5rem));
  max-height: calc(100dvh - 1.5rem);
  margin: auto;
  padding: .625rem;
  border: 1px solid var(--border);
  border-radius: 1rem;
  background: var(--background);
  color: var(--foreground);
}

.preview::backdrop { background: #09182bc2; }
.preview-header { display: flex; align-items: center; justify-content: space-between; gap: 1rem; padding-inline: .3125rem; }
.preview-header h2 { margin: 0; font-size: 1rem; font-weight: 650; }
.preview img { display: block; max-width: 100%; max-height: calc(100dvh - 6.25rem); margin-inline: auto; border-radius: .625rem; }

@media (max-width: 760px) {
  .hero {
    grid-template-columns: minmax(0, 1fr);
    align-content: center;
    gap: clamp(1.625rem, 6.5vw, 2.75rem);
    padding: 1.125rem clamp(1.625rem, 7vw, 4.25rem);
  }
  .hero-copy {
    display: grid;
    justify-items: center;
    text-align: center;
  }
  .hero-logo { font-size: clamp(2.6rem, 9vw, 3.5rem); }
  .hero-summary {
    margin-top: clamp(.75rem, 2.5dvh - .6rem, 1.375rem);
    font-size: 1rem;
  }
  .capabilities {
    grid-template-columns: minmax(4.75rem, 26%) minmax(0, 1fr);
    gap: clamp(.375rem, .85dvh, .6875rem) .625rem;
    width: fit-content;
    margin-top: clamp(.875rem, 3.3dvh - .8125rem, 1.75rem);
    text-align: start;
    font-size: .8125rem;
  }
  .capability dd span { padding-inline: .375rem; line-height: 1.5; }
  .showcase { --shot-width: clamp(6.75rem, 29vw, 11rem); width: min(100%, 26.25rem); }
  .screen { padding: .25rem; }
  .timer { left: 9%; top: 3%; }
  .statistics { right: 7%; top: 12%; rotate: 7deg; }
}

@media (min-width: 360px) and (max-width: 760px) {
  /* Trailing full-width punctuation makes both centered Chinese lines appear left of the logo. */
  .hero-summary:lang(zh-Hans) > span { translate: .4em 0; }
}
</style>
