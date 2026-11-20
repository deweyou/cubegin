<script setup lang="ts">
import { Languages } from '@lucide/vue'
import cubeginLogo from '../../../ios/Design/LegacyIcons/brand/svg/cubegin-lockup.svg?url'
import { Button } from '~/components/ui/button'

const route = useRoute()
const isEnglish = computed(() => route.path === '/en' || route.path.startsWith('/en/'))
const languagePath = computed(() => isEnglish.value ? route.path.slice('/en'.length) || '/' : '/en' + route.path)
const languageLabel = computed(() => isEnglish.value ? 'Switch to Simplified Chinese' : '切换到英文')
</script>

<template>
  <header class="site-header">
    <div class="site-frame header-content">
      <NuxtLink :to="isEnglish ? '/en' : '/'" class="brand">
        <img :src="cubeginLogo" alt="Cubegin" width="714" height="200" />
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
    </div>
  </header>
  <slot />
</template>
