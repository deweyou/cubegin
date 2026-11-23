<script setup lang="ts">
import { Languages, Moon, Sun } from '@lucide/vue'
import cubeginDarkLogo from '../../../ios/Design/LegacyIcons/brand/svg/cubegin-lockup-dark.svg?url'
import cubeginLogo from '../../../ios/Design/LegacyIcons/brand/svg/cubegin-lockup.svg?url'
import { Button } from '~/components/ui/button'
import { themeStorageKey } from '~/lib/theme'

const route = useRoute()
const isEnglish = computed(() => route.path === '/en' || route.path.startsWith('/en/'))
const isHome = computed(() => /^\/(?:en\/?)?$/.test(route.path))
const languagePath = computed(() => isEnglish.value ? route.path.slice('/en'.length) || '/' : '/en' + route.path)
const languageLabel = computed(() => isEnglish.value ? 'Switch to Simplified Chinese' : '切换到英文')
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
  <header>
    <div :class="isHome ? 'home-toolbar' : 'site-frame header-content'">
      <NuxtLink v-if="!isHome" :to="isEnglish ? '/en' : '/'" class="brand">
        <img :src="cubeginLogo" alt="Cubegin" width="714" height="200" class="brand-light" />
        <img :src="cubeginDarkLogo" alt="Cubegin" width="714" height="200" class="brand-dark" />
      </NuxtLink>
      <div class="flex items-center gap-1" :class="{ 'home-controls': isHome }">
        <Button as-child variant="ghost" size="icon" class="size-11">
          <NuxtLink
            :to="languagePath"
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
  <footer v-if="isHome" class="home-footer">
    <NuxtLink :to="isEnglish ? '/en/feedback' : '/feedback'">
      {{ isEnglish ? 'Product feedback' : '产品反馈' }}
    </NuxtLink>
    <NuxtLink :to="isEnglish ? '/en/privacy' : '/privacy'">
      {{ isEnglish ? 'Privacy policy' : '隐私政策' }}
    </NuxtLink>
  </footer>
</template>

<style scoped>
.home-toolbar {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  min-height: var(--home-toolbar-height);
  padding-inline: clamp(1rem, 4vw, 4rem);
}

.home-controls { gap: .75rem; }

.home-footer {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  min-height: var(--home-footer-height);
  color: var(--muted-foreground);
  font-size: .8125rem;
}

.home-footer a {
  display: inline-flex;
  align-items: center;
  min-height: var(--home-footer-height);
  padding-inline: .375rem;
}

.home-footer a:hover {
  color: var(--foreground);
  text-decoration: underline;
  text-underline-offset: .2em;
}
</style>
