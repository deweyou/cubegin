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
const themeLabel = computed(() => {
  if (isEnglish.value) return isDark.value ? 'Switch to light mode' : 'Switch to dark mode'
  return isDark.value ? '切换到浅色主题' : '切换到深色主题'
})
let systemTheme: MediaQueryList | undefined

function syncTheme() {
  const preferredTheme = document.documentElement.dataset.theme
  isDark.value = preferredTheme ? preferredTheme === 'dark' : systemTheme?.matches === true
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
    <div class="site-frame header-content" :class="{ 'home-header': isHome }">
      <NuxtLink :to="isEnglish ? '/en' : '/'" class="brand">
        <img :src="cubeginLogo" alt="Cubegin" width="714" height="200" class="brand-light" />
        <img :src="cubeginDarkLogo" alt="Cubegin" width="714" height="200" class="brand-dark" />
      </NuxtLink>
      <div class="flex items-center gap-1">
        <NuxtLink v-if="isHome" :to="isEnglish ? '/en/privacy' : '/privacy'" class="rounded-md px-2 py-2 text-sm hover:underline">
          {{ isEnglish ? 'Privacy policy' : '隐私政策' }}
        </NuxtLink>
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
</template>

<style scoped>
.home-header {
  width: auto;
  margin-inline: clamp(1rem, 4vw, 4rem);
}
</style>
