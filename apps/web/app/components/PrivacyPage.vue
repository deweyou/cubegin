<script setup lang="ts">
import { policies, type PolicyLanguage } from '~/lib/privacy'

const props = defineProps<{ language: PolicyLanguage }>()
const policy = computed(() => policies[props.language])
const heading = computed(() => policy.value.title.replace(/^Cubegin\s+/, ''))

useSiteSeo(
  'privacy',
  () => props.language,
  () => policy.value.title,
  () => props.language === 'en'
    ? 'Learn what data Cubegin collects, how it is used, and how to manage your privacy choices.'
    : '了解 Cubegin 收集哪些数据、如何使用这些数据，以及如何管理你的隐私选择。',
)
</script>

<template>
  <main class="site-frame site-page">
    <h1>{{ heading }}</h1>
    <article class="policy-body" v-html="policy.html" />
  </main>
</template>
