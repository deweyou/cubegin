<script setup lang="ts">
import darkStatisticsScreenshot from '~/assets/images/iphone-statistics-dark.jpg?url'
import lightStatisticsScreenshot from '~/assets/images/iphone-statistics-light.jpg?url'
import darkTimerScreenshot from '~/assets/images/iphone-timer-dark.jpg?url'
import lightTimerScreenshot from '~/assets/images/iphone-timer-light.jpg?url'
import { Button } from '~/components/ui/button'

const props = defineProps<{ language: 'zh-Hans' | 'en' }>()

const copy = {
  'zh-Hans': {
    title: '魔方速拧计时器',
    titleLead: '魔方速拧',
    titleEnd: '计时器',
    description: '练习打乱，记录每次还原。',
    platforms: '支持 iPhone、iPhone Duo 和 iPad',
    screenshots: '查看 App 截图',
    close: '关闭',
    timer: '计时页',
    statistics: '统计页',
    enlargeTimer: '放大计时页',
    enlargeStatistics: '放大统计页',
  },
  en: {
    title: 'Speedcubing timer',
    titleLead: 'Speedcubing',
    titleEnd: 'timer',
    description: 'Practice scrambles and record every solve.',
    platforms: 'For iPhone, iPhone Duo, and iPad',
    screenshots: 'View app screenshots',
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
const description = computed(() => `${content.value.description} ${content.value.platforms}`)
const dialog = useTemplateRef<HTMLDialogElement>('preview')
const selectedScreenshot = ref<Screenshot>('timer')
const themePreference = useThemePreference()
const darkScreenshotMedia = computed(() => {
  if (themePreference.value === 'dark') return 'all'
  if (themePreference.value === 'light') return 'not all'
  return '(prefers-color-scheme: dark)'
})

useHead(() => ({ htmlAttrs: { lang: props.language } }))
useSeoMeta({
  title: () => `Cubegin | ${content.value.title}`,
  description: () => description.value,
})

function showScreenshot(screenshot: Screenshot) {
  selectedScreenshot.value = screenshot
  dialog.value?.showModal()
}
</script>

<template>
  <main class="home">
    <section class="hero" aria-labelledby="home-title">
      <div class="hero-copy">
        <h1 id="home-title" :aria-label="content.title">
          {{ content.titleLead }}<br>{{ language === "en" ? " " + content.titleEnd : content.titleEnd }}
        </h1>
        <p class="description">{{ content.description }}</p>
        <p class="platforms">{{ content.platforms }}</p>
        <Button type="button" class="hero-button" @click="showScreenshot('timer')">
          {{ content.screenshots }}
        </Button>
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
.home {
  min-height: calc(100dvh - 4.25rem);
  padding-inline: clamp(.625rem, 2vw, 2rem);
  padding-bottom: clamp(3.5rem, 10dvh, 6.5rem);
}

.hero {
  --brand-blue: #2f7ce0;
  --hero-fill: color-mix(in srgb, var(--primary) 68%, var(--brand-blue));
  --hero-foreground: #f9fcff;
  --hero-muted: #e2eeff;
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1.13fr);
  align-items: center;
  gap: clamp(.75rem, 4vw, 4rem);
  min-height: clamp(30rem, calc(100dvh - 9.5rem), 49rem);
  padding: 2.2rem clamp(1.875rem, 6vw, 6.5rem);
  border-radius: clamp(1rem, 2.4vw, 2.125rem);
  background: light-dark(var(--hero-fill), #193d73);
  color: var(--hero-foreground);
}

.hero-copy h1 {
  margin: 0;
  font-size: clamp(2.6rem, 6.1vw, 6rem);
  font-weight: 755;
  line-height: 1.04;
  letter-spacing: -.07em;
}

.description {
  margin-top: 1.375rem;
  font-size: clamp(1rem, 1.45vw, 1.25rem);
  line-height: 1.55;
}

.platforms {
  margin-top: .6875rem;
  color: var(--hero-muted);
  font-size: .875rem;
  line-height: 1.6;
}

.hero-button {
  height: 2.875rem;
  margin-top: 1.5625rem;
  background: #f8fbff;
  color: #0755a2;
  font-weight: 700;
}

.hero-button:hover { background: #e4f0ff; }

.showcase {
  --shot-width: clamp(9.6875rem, min(20.4vw, 35dvh), 18.875rem);
  position: relative;
  width: min(100%, 36.875rem);
  height: clamp(26.25rem, 68dvh, 39rem);
  margin-inline: auto;
}

.screen {
  position: absolute;
  width: var(--shot-width);
  padding: .375rem;
  border: 1px solid #25365148;
  border-radius: clamp(.9375rem, 1.65vw, 1.625rem);
  background: light-dark(#f9fafa, #25282e);
  box-shadow: 0 1.5rem 3.4375rem #071d4661;
  cursor: zoom-in;
}

.screen:focus-visible, .hero-button:focus-visible {
  outline: 2px solid var(--hero-foreground);
  outline-offset: 3px;
}

.screen picture { display: block; border-radius: inherit; }
.screen img { display: block; width: 100%; height: auto; border-radius: inherit; }
.timer { z-index: 1; left: 2%; top: 1%; rotate: -8deg; }
.statistics { right: 2%; top: 13%; rotate: 8deg; }

@media (hover: hover) {
  .screen:hover { translate: 0 -.3125rem; }
}

@media (prefers-reduced-motion: no-preference) {
  .screen { transition: translate .16s ease-out; }
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
  .home { padding-bottom: 1.75rem; }
  .hero {
    grid-template-columns: minmax(0, 1fr);
    align-content: center;
    gap: 1.5625rem;
    min-height: calc(100dvh - 6rem);
    padding: 1.75rem clamp(1rem, 5vw, 2.25rem) .375rem;
  }
  .hero-copy h1 { font-size: clamp(2rem, 8vw, 3.5rem); }
  .hero-copy h1 br { display: none; }
  .description { margin-top: .625rem; }
  .platforms { margin-top: .375rem; font-size: .8125rem; }
  .showcase { --shot-width: clamp(6.75rem, 34vw, 11rem); height: clamp(17.1875rem, 45dvh, 26rem); width: min(100%, 26.25rem); }
  .screen { padding: .25rem; }
  .timer { left: 9%; top: 3%; }
  .statistics { right: 7%; top: 12%; rotate: 7deg; }
}
</style>
