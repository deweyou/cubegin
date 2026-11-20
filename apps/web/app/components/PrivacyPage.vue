<script setup lang="ts">
import { policies, type PolicyLanguage } from '~/lib/privacy'

const props = defineProps<{ language: PolicyLanguage }>()
const policy = computed(() => policies[props.language])
const heading = computed(() => policy.value.title.replace(/^Cubegin\s+/, ''))

useHead(() => ({
  title: policy.value.title,
  htmlAttrs: { lang: props.language },
}))
</script>

<template>
  <main class="site-frame policy-page">
    <h1>{{ heading }}</h1>
    <article class="policy-body" v-html="policy.html" />
  </main>
</template>
