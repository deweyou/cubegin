<script setup lang="ts">
import { Button } from '~/components/ui/button'
import { policies, type PolicyLanguage } from '~/lib/privacy'

const props = defineProps<{ language: PolicyLanguage }>()
const isEnglish = computed(() => props.language === 'en')
const policy = computed(() => policies[props.language])

useHead(() => ({
  title: policy.value.title,
  htmlAttrs: { lang: props.language },
}))
</script>

<template>
  <main class="site-frame policy-page">
    <div class="policy-heading">
      <h1>{{ policy.title }}</h1>
      <Button as-child variant="outline" size="sm" class="language-switch">
        <NuxtLink
          :to="isEnglish ? '/privacy' : '/en/privacy'"
          :lang="isEnglish ? 'zh-Hans' : 'en'"
          :hreflang="isEnglish ? 'zh-Hans' : 'en'"
        >
          {{ isEnglish ? '简体中文' : 'English' }}
        </NuxtLink>
      </Button>
    </div>

    <div class="policy-layout">
      <nav class="policy-nav" :aria-label="isEnglish ? 'Contents' : '目录'">
        <p>{{ isEnglish ? 'On this page' : '本页目录' }}</p>
        <ul>
          <li v-for="section in policy.sections" :key="section.id">
            <a :href="'#' + section.id">{{ section.label }}</a>
          </li>
        </ul>
      </nav>
      <article class="policy-body" v-html="policy.html" />
    </div>
  </main>
</template>
