<script setup lang="ts">
import { ArrowUpRight } from '@lucide/vue'
import { Button } from '~/components/ui/button'
import type { PolicyLanguage } from '~/lib/privacy'

const props = defineProps<{ language: PolicyLanguage }>()
const copy = computed(() => props.language === 'en' ? {
  title: 'Feedback & Reviews',
  message: 'Feedback',
  email: 'Email (optional)',
  emailHelp: 'Leave your email if you’d like a reply.',
  send: 'Send feedback',
  sending: 'Sending…',
  sent: 'Feedback sent. Thank you!',
  failed: 'Couldn’t send feedback. Please try again.',
  review: 'Review on the App Store',
  privacy: 'Privacy Policy',
  privacyPath: '/en/privacy',
} : {
  title: '反馈与评价',
  message: '反馈内容',
  email: '邮箱（选填）',
  emailHelp: '如果希望收到回复，请留下邮箱。',
  send: '发送反馈',
  sending: '正在发送…',
  sent: '反馈已发送，谢谢！',
  failed: '反馈发送失败，请重试。',
  review: '在 App Store 评价',
  privacy: '隐私政策',
  privacyPath: '/privacy',
})

const { appStoreId } = useRuntimeConfig().public
const reviewURL = /^\d+$/.test(appStoreId)
  ? `https://apps.apple.com/app/id${appStoreId}?action=write-review`
  : undefined
const message = ref('')
const email = ref('')
const website = ref('')
const status = ref<'idle' | 'sending' | 'sent' | 'failed'>('idle')
let attempt: { message: string; email: string; requestId: string } | undefined

useHead(() => ({
  title: `${copy.value.title} | Cubegin`,
  htmlAttrs: { lang: props.language },
}))

async function sendFeedback() {
  const trimmedMessage = message.value.trim()
  const trimmedEmail = email.value.trim()
  if (!trimmedMessage || status.value === 'sending') return

  if (attempt?.message !== trimmedMessage || attempt?.email !== trimmedEmail) {
    attempt = { message: trimmedMessage, email: trimmedEmail, requestId: crypto.randomUUID() }
  }
  status.value = 'sending'
  try {
    const response = await $fetch<{ sent: boolean }>('/api/feedback', {
      method: 'POST',
      body: { ...attempt, website: website.value },
    })
    if (response?.sent !== true) {
      status.value = 'failed'
      return
    }
    message.value = ''
    email.value = ''
    attempt = undefined
    status.value = 'sent'
  } catch {
    status.value = 'failed'
  }
}
</script>

<template>
  <main class="site-frame policy-page">
    <h1>{{ copy.title }}</h1>
    <form class="grid max-w-xl gap-5" @submit.prevent="sendFeedback">
      <div class="grid gap-2">
        <label for="feedback-message" class="font-semibold">{{ copy.message }}</label>
        <textarea
          id="feedback-message"
          v-model="message"
          required
          maxlength="4000"
          rows="6"
          :readonly="status === 'sending'"
          class="feedback-input min-h-32 resize-y"
        />
      </div>
      <div class="grid gap-2">
        <label for="feedback-email" class="font-semibold">{{ copy.email }}</label>
        <input
          id="feedback-email"
          v-model="email"
          type="email"
          autocomplete="email"
          maxlength="254"
          aria-describedby="feedback-email-help"
          :readonly="status === 'sending'"
          class="feedback-input"
        />
        <p id="feedback-email-help" class="text-sm text-(--muted-foreground)">{{ copy.emailHelp }}</p>
      </div>
      <div hidden>
        <label for="feedback-website">Website</label>
        <input id="feedback-website" v-model="website" type="text" tabindex="-1" autocomplete="off" />
      </div>
      <div class="flex flex-wrap items-center gap-4">
        <Button type="submit" :disabled="status === 'sending' || !message.trim()">
          {{ status === 'sending' ? copy.sending : copy.send }}
        </Button>
        <NuxtLink :to="copy.privacyPath" class="text-sm text-primary underline underline-offset-4">
          {{ copy.privacy }}
        </NuxtLink>
      </div>
      <p v-if="status === 'sent'" role="status">{{ copy.sent }}</p>
      <p v-if="status === 'failed'" role="alert" class="text-destructive">{{ copy.failed }}</p>
    </form>
    <div v-if="reviewURL" class="mt-8 max-w-xl border-t border-border pt-5">
      <a :href="reviewURL" class="inline-flex min-h-11 items-center gap-2 font-semibold text-primary">
        {{ copy.review }}
        <ArrowUpRight aria-hidden="true" class="size-4" />
      </a>
    </div>
  </main>
</template>

<style scoped>
.feedback-input {
  width: 100%;
  min-height: 2.75rem;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--background);
  padding: 0.625rem 0.75rem;
}

.feedback-input:focus-visible {
  outline: 2px solid var(--ring);
  outline-offset: 2px;
}
</style>
