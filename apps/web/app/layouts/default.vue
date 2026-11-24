<script setup lang="ts">
import { Languages, Mail, Moon, Sun } from '@lucide/vue'
import cubeginDarkLogo from '../../../ios/Design/LegacyIcons/brand/svg/cubegin-lockup-dark.svg?url'
import cubeginLogo from '../../../ios/Design/LegacyIcons/brand/svg/cubegin-lockup.svg?url'
import { Button } from '~/components/ui/button'
import { themeStorageKey } from '~/lib/theme'

const route = useRoute()
const isEnglish = computed(() => route.path === '/en' || route.path.startsWith('/en/'))
const homePath = computed(() => isEnglish.value ? '/en/' : '/')
const playgroundPath = computed(() => isEnglish.value ? '/en/playground/' : '/playground/')
const languagePath = computed(() => isEnglish.value ? route.path.slice('/en'.length) || '/' : '/en' + route.path)
const languageLabel = computed(() => isEnglish.value ? 'Switch to Simplified Chinese' : '切换到英文')
const supportEmailLabel = computed(() => isEnglish.value ? 'Email support' : '邮件联系')
const isDark = ref(false)
const themeReady = ref(false)
const themePreference = useThemePreference()
const themeLabel = computed(() => {
  if (isEnglish.value) return isDark.value ? 'Switch to light mode' : 'Switch to dark mode'
  return isDark.value ? '切换到浅色主题' : '切换到深色主题'
})
let systemTheme: MediaQueryList | undefined

function syncTheme() {
  const preferredTheme = document.documentElement.dataset.theme
  themePreference.value = preferredTheme === 'light' || preferredTheme === 'dark' ? preferredTheme : undefined
  isDark.value = themePreference.value ? themePreference.value === 'dark' : systemTheme?.matches === true
}

function toggleTheme() {
  const theme = isDark.value ? 'light' : 'dark'
  document.documentElement.dataset.theme = theme
  syncTheme()
  try {
    localStorage.setItem(themeStorageKey, theme)
  } catch {
    // The current page can still switch themes when browser storage is unavailable.
  }
}

onMounted(() => {
  systemTheme = window.matchMedia('(prefers-color-scheme: dark)')
  syncTheme()
  systemTheme.addEventListener('change', syncTheme)
  themeReady.value = true
})

onBeforeUnmount(() => {
  systemTheme?.removeEventListener('change', syncTheme)
})
</script>

<template>
  <header class="site-header">
    <div class="site-toolbar">
      <NuxtLink :to="homePath" class="brand">
        <img :src="cubeginLogo" alt="Cubegin" width="714" height="200" class="brand-light" />
        <img :src="cubeginDarkLogo" alt="Cubegin" width="714" height="200" class="brand-dark" />
      </NuxtLink>
      <nav class="site-nav" :aria-label="isEnglish ? 'Main navigation' : '主导航'">
        <NuxtLink :to="homePath" class="nav-link">{{ isEnglish ? 'Home' : '首页' }}</NuxtLink>
        <NuxtLink :to="playgroundPath" class="nav-link">{{ isEnglish ? 'Playground' : '调试台' }}</NuxtLink>
      </nav>
      <div class="site-controls">
        <Button as-child variant="ghost" size="icon" class="size-11">
          <NuxtLink
            :to="{ path: languagePath, query: route.query, hash: route.hash }"
            :aria-label="languageLabel"
            :title="languageLabel"
            :hreflang="isEnglish ? 'zh-Hans' : 'en'"
          >
            <Languages aria-hidden="true" class="size-5" />
          </NuxtLink>
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="icon"
          class="size-11"
          :aria-label="themeLabel"
          :title="themeLabel"
          :disabled="!themeReady"
          @click="toggleTheme"
        >
          <Sun v-if="isDark" aria-hidden="true" class="size-5" />
          <Moon v-else aria-hidden="true" class="size-5" />
        </Button>
        <Button as-child variant="ghost" size="icon" class="size-11">
          <a href="mailto:deweyou97@gmail.com" :aria-label="supportEmailLabel" :title="supportEmailLabel">
            <Mail aria-hidden="true" class="size-5" />
          </a>
        </Button>
      </div>
    </div>
  </header>
  <slot />
</template>

<style scoped>
.site-header {
  border-bottom: 1px solid color-mix(in srgb, var(--border) 68%, transparent);
}

.site-toolbar {
  display: flex;
  align-items: center;
  gap: clamp(.5rem, 2vw, 1.75rem);
  min-height: var(--site-header-height);
  padding: .5rem clamp(.75rem, 4vw, 4rem) 0;
}

.site-toolbar .brand img { height: clamp(1.375rem, 4vw, 2rem); }

.site-nav, .site-controls {
  display: flex;
  align-items: center;
  gap: .25rem;
}

.site-controls { margin-inline-start: auto; }
.site-controls > :is(a, button), .nav-link { color: var(--muted-foreground); }
.site-controls > :is(a, button):hover { color: var(--foreground); }

.nav-link {
  display: inline-flex;
  align-items: center;
  min-height: 2.5rem;
  padding-inline: .65rem;
  border-radius: .5rem;
  font-size: .875rem;
  font-weight: 600;
  white-space: nowrap;
}

.nav-link:hover { color: var(--foreground); }

.nav-link[aria-current="page"] {
  color: var(--primary);
  font-weight: 700;
}

@media (max-width: 540px) {
  .site-controls { gap: 0; }
  .site-controls > :is(a, button) { width: 2.25rem; }
  .nav-link { padding-inline: .375rem; font-size: .8125rem; }
}

@media (max-width: 360px) {
  .site-toolbar { padding-inline: .5rem; gap: .25rem; }
  .site-toolbar .brand img { height: 1.2rem; }
  .site-nav { gap: 0; }
  .nav-link { padding-inline: .25rem; }
}
</style>
