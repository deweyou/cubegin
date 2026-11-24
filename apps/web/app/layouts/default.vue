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
      </div>
    </div>
  </header>
  <slot />
  <footer class="site-footer">
    <Button as-child variant="ghost" size="icon" class="size-11">
      <a href="https://github.com/deweyou/cubegin" aria-label="Cubegin GitHub" title="Cubegin GitHub">
        <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" class="size-5">
          <path d="M12 .297a12 12 0 0 0-3.793 23.386c.6.113.82-.258.82-.577l-.016-2.232c-3.338.726-4.042-1.61-4.042-1.61-.546-1.387-1.333-1.756-1.333-1.756-1.09-.745.083-.73.083-.73 1.205.084 1.84 1.237 1.84 1.237 1.07 1.835 2.809 1.305 3.495.998.108-.776.418-1.305.762-1.605-2.665-.303-5.467-1.333-5.467-5.932 0-1.31.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23a11.51 11.51 0 0 1 6.006 0c2.291-1.552 3.297-1.23 3.297-1.23.654 1.652.243 2.873.12 3.176.77.84 1.235 1.91 1.235 3.221 0 4.61-2.807 5.626-5.479 5.923.43.372.814 1.103.814 2.222 0 1.606-.015 2.898-.015 3.292 0 .322.216.696.825.577A12 12 0 0 0 12 .297Z"/>
        </svg>
      </a>
    </Button>
    <Button as-child variant="ghost" size="icon" class="size-11">
      <a href="mailto:deweyou97@gmail.com" :aria-label="supportEmailLabel" :title="supportEmailLabel">
        <Mail aria-hidden="true" class="size-5" />
      </a>
    </Button>
  </footer>
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

.site-footer {
  display: flex;
  justify-content: center;
  align-items: center;
  gap: .25rem;
  min-height: var(--site-footer-height);
  margin-top: auto;
  color: var(--muted-foreground);
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
