<script setup lang="ts">
const route = useRoute()
const isEnglish = computed(() => route.path === '/en' || route.path.startsWith('/en/'))
</script>

<template>
  <header class="site-header">
    <div class="site-frame header-content">
      <NuxtLink :to="isEnglish ? '/en' : '/'" class="brand">
        <span aria-hidden="true" class="cube-mark">
          <span v-for="cell in 9" :key="cell" />
        </span>
        Cubegin
      </NuxtLink>
    </div>
  </header>
  <slot />
</template>
