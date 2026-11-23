<script setup lang="ts">
import { ArrowUpRight, X } from '@lucide/vue'
import { Button } from '~/components/ui/button'
import { compressScreenshot, maxScreenshots } from '~/lib/feedback-image'
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
  limited: 'Feedback is receiving too many requests. Please try again later.',
  screenshots: 'Screenshots (optional)',
  addScreenshots: 'Add screenshots',
  screenshotHelp: 'Add up to three JPEG or PNG screenshots.',
  processing: 'Preparing screenshots…',
  tooMany: 'You can attach up to three screenshots.',
  imageFailed: 'Some screenshots couldn’t be added. Choose a JPEG or PNG and try again.',
  removeImage: (index: number) => `Remove screenshot ${index + 1}`,
  screenshotAlt: (index: number) => `Screenshot ${index + 1}`,
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
  limited: '反馈提交过于频繁，请稍后重试。',
  screenshots: '截图（选填）',
  addScreenshots: '添加截图',
  screenshotHelp: '最多添加 3 张 JPEG 或 PNG 截图。',
  processing: '正在处理截图…',
  tooMany: '最多可添加 3 张截图。',
  imageFailed: '部分截图无法添加，请选择 JPEG 或 PNG 图片后重试。',
  removeImage: (index: number) => `移除第 ${index + 1} 张截图`,
  screenshotAlt: (index: number) => `截图 ${index + 1}`,
  review: '在 App Store 评价',
  privacy: '隐私政策',
  privacyPath: '/privacy',
})

const { appStoreId, feedbackEndpoint } = useRuntimeConfig().public
const endpoint = feedbackEndpoint || (import.meta.dev ? 'http://127.0.0.1:4490/api/feedback' : '/api/feedback')
const reviewURL = /^\d+$/.test(appStoreId)
  ? `https://apps.apple.com/app/id${appStoreId}?action=write-review`
  : undefined
const message = ref('')
const email = ref('')
const website = ref('')
const status = ref<'idle' | 'sending' | 'sent' | 'failed' | 'limited'>('idle')
const screenshots = shallowRef<{ image: Blob; preview: string }[]>([])
const screenshotInput = ref<HTMLInputElement | null>(null)
const isPreparing = ref(false)
const screenshotError = ref<'tooMany' | 'imageFailed'>()
let attempt: { message: string; email: string; requestId: string; screenshots: typeof screenshots.value } | undefined
let isMounted = true

useHead(() => ({
  title: `${copy.value.title} | Cubegin`,
  htmlAttrs: { lang: props.language },
}))

async function sendFeedback() {
  const trimmedMessage = message.value.trim()
  const trimmedEmail = email.value.trim()
  if (!trimmedMessage || status.value === 'sending' || isPreparing.value) return

  if (attempt?.message !== trimmedMessage || attempt?.email !== trimmedEmail || attempt?.screenshots !== screenshots.value) {
    attempt = { message: trimmedMessage, email: trimmedEmail, requestId: crypto.randomUUID(), screenshots: screenshots.value }
  }
  const body = new FormData()
  body.set('message', attempt.message)
  body.set('email', attempt.email)
  body.set('requestId', attempt.requestId)
  body.set('website', website.value)
  for (const [index, screenshot] of attempt.screenshots.entries()) {
    body.append('images', screenshot.image, `screenshot-${index + 1}.jpg`)
  }
  status.value = 'sending'
  try {
    const response = await $fetch<{ sent: boolean }>(endpoint, { method: 'POST', body, retry: 0 })
    if (response?.sent !== true) {
      status.value = 'failed'
      return
    }
    message.value = ''
    email.value = ''
    for (const screenshot of screenshots.value) URL.revokeObjectURL(screenshot.preview)
    screenshots.value = []
    screenshotError.value = undefined
    attempt = undefined
    status.value = 'sent'
  } catch (error) {
    status.value = (error as { statusCode?: number }).statusCode === 429 ? 'limited' : 'failed'
  }
}

async function addScreenshots(event: Event) {
  const input = event.target as HTMLInputElement
  const files = Array.from(input.files ?? [])
  input.value = ''
  if (!files.length || isPreparing.value || status.value === 'sending') return
  if (files.length + screenshots.value.length > maxScreenshots) {
    screenshotError.value = 'tooMany'
    return
  }
  screenshotError.value = undefined
  isPreparing.value = true
  try {
    for (const file of files) {
      try {
        const image = await compressScreenshot(file)
        if (!isMounted) break
        screenshots.value = [...screenshots.value, { image, preview: URL.createObjectURL(image) }]
      } catch {
        screenshotError.value = 'imageFailed'
      }
    }
  } finally {
    isPreparing.value = false
  }
}

function removeScreenshot(index: number) {
  const screenshot = screenshots.value[index]
  if (!screenshot) return
  URL.revokeObjectURL(screenshot.preview)
  screenshots.value = screenshots.value.filter((_, current) => current !== index)
  screenshotError.value = undefined
}

onBeforeUnmount(() => {
  isMounted = false
  for (const screenshot of screenshots.value) URL.revokeObjectURL(screenshot.preview)
})
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
      <div class="grid gap-2">
        <label for="feedback-screenshots" class="font-semibold">{{ copy.screenshots }}</label>
        <p id="feedback-screenshot-help" class="text-sm text-(--muted-foreground)">{{ copy.screenshotHelp }}</p>
        <input
          id="feedback-screenshots"
          ref="screenshotInput"
          type="file"
          accept="image/jpeg,image/png"
          multiple
          :disabled="isPreparing || status === 'sending' || screenshots.length === maxScreenshots"
          aria-describedby="feedback-screenshot-help"
          class="sr-only"
          tabindex="-1"
          @change="addScreenshots"
        />
        <Button
          type="button" variant="outline" class="w-fit"
          :disabled="isPreparing || status === 'sending' || screenshots.length === maxScreenshots"
          aria-describedby="feedback-screenshot-help"
          @click="screenshotInput?.click()"
        >
          {{ copy.addScreenshots }} ({{ screenshots.length }}/{{ maxScreenshots }})
        </Button>
        <ul v-if="screenshots.length" class="grid grid-cols-3 gap-2">
          <li v-for="(screenshot, index) in screenshots" :key="screenshot.preview" class="grid min-w-0 justify-items-center">
            <img :src="screenshot.preview" :alt="copy.screenshotAlt(index)" class="h-24 w-full rounded-md border border-border object-contain" />
            <Button
              type="button" variant="ghost" size="icon" class="size-11"
              :aria-label="copy.removeImage(index)" :disabled="status === 'sending' || isPreparing"
              @click="removeScreenshot(index)"
            >
              <X aria-hidden="true" />
            </Button>
          </li>
        </ul>
        <p v-if="isPreparing" role="status" class="text-sm">{{ copy.processing }}</p>
        <p v-if="screenshotError" role="alert" class="text-sm text-destructive">{{ copy[screenshotError] }}</p>
      </div>
      <div hidden>
        <label for="feedback-website">Website</label>
        <input id="feedback-website" v-model="website" type="text" tabindex="-1" autocomplete="off" />
      </div>
      <div class="flex flex-wrap items-center gap-4">
        <Button type="submit" :disabled="status === 'sending' || isPreparing || !message.trim()">
          {{ status === 'sending' ? copy.sending : copy.send }}
        </Button>
        <NuxtLink :to="copy.privacyPath" class="text-sm text-primary underline underline-offset-4">
          {{ copy.privacy }}
        </NuxtLink>
      </div>
      <p v-if="status === 'sent'" role="status">{{ copy.sent }}</p>
      <p v-if="status === 'failed'" role="alert" class="text-destructive">{{ copy.failed }}</p>
      <p v-if="status === 'limited'" role="alert" class="text-destructive">{{ copy.limited }}</p>
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
