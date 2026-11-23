<script setup lang="ts">
import { ArrowUpRight, CircleX, Info, LoaderCircle, Plus, Send, X } from '@lucide/vue'
import { Button } from '~/components/ui/button'
import { Card } from '~/components/ui/card'
import { Input } from '~/components/ui/input'
import { Textarea } from '~/components/ui/textarea'
import { compressScreenshot, maxScreenshots } from '~/lib/feedback-image'
import type { PolicyLanguage } from '~/lib/privacy'

const props = defineProps<{ language: PolicyLanguage }>()
const copy = computed(() => props.language === 'en' ? {
  title: 'Feedback & Reviews',
  message: 'Feedback',
  placeholder: 'Describe your issue or suggestion',
  email: 'Email (optional)',
  emailHelp: 'Leave your email if you’d like a reply.',
  send: 'Send feedback',
  sending: 'Sending…',
  sent: 'Feedback sent. Thank you!',
  failed: 'Couldn’t send feedback. Please try again.',
  limited: 'Feedback is receiving too many requests. Please try again later.',
  screenshots: 'Screenshots (optional)',
  addScreenshots: 'Add screenshots',
  processing: 'Preparing screenshots…',
  tooMany: 'You can attach up to three screenshots.',
  imageFailed: 'Some screenshots couldn’t be added. Choose a JPEG or PNG and try again.',
  missingMessage: 'Enter your feedback first.',
  longMessage: (limit: number) => `Feedback must be ${limit} characters or fewer.`,
  invalidEmail: 'Enter a valid email address.',
  clearMessage: 'Clear feedback',
  clearEmail: 'Clear email',
  characterCount: (count: number, limit: number) => `${count} of ${limit} characters`,
  removeImage: (index: number) => `Remove screenshot ${index + 1}`,
  screenshotAlt: (index: number) => `Screenshot ${index + 1}`,
  review: 'Review on the App Store',
  privacy: 'Privacy Policy',
  privacyPath: '/en/privacy',
} : {
  title: '反馈与评价',
  message: '反馈内容',
  placeholder: '请描述你的问题或建议',
  email: '邮箱（选填）',
  emailHelp: '留下邮箱，方便我们回复你的反馈。',
  send: '发送反馈',
  sending: '正在发送…',
  sent: '反馈已发送，谢谢！',
  failed: '反馈发送失败，请重试。',
  limited: '反馈提交过于频繁，请稍后重试。',
  screenshots: '截图（选填）',
  addScreenshots: '添加截图',
  processing: '正在处理截图…',
  tooMany: '最多可添加 3 张截图。',
  imageFailed: '部分截图无法添加，请选择 JPEG 或 PNG 图片后重试。',
  missingMessage: '请先填写反馈内容。',
  longMessage: (limit: number) => `反馈内容不能超过 ${limit} 字符。`,
  invalidEmail: '请输入有效的邮箱地址。',
  clearMessage: '清空反馈内容',
  clearEmail: '清空邮箱',
  characterCount: (count: number, limit: number) => `${count} / ${limit} 字符`,
  removeImage: (index: number) => `移除第 ${index + 1} 张截图`,
  screenshotAlt: (index: number) => `截图 ${index + 1}`,
  review: '在 App Store 评价',
  privacy: '隐私政策',
  privacyPath: '/privacy',
})

const maxMessageLength = 200
const savedEmailKey = 'cubegin.feedback.replyEmail'
const emailPattern = /^[^\s@<>,;\p{Cc}]+@[^\s@<>,;\p{Cc}]+\.[^\s@<>,;\p{Cc}]+$/u
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
const validationNotice = ref<{ message: string; shownAt: number }>()
let noticeTimer: ReturnType<typeof setTimeout> | undefined
let attempt: { message: string; email: string; requestId: string; screenshots: typeof screenshots.value } | undefined
let isMounted = true

const trimmedMessage = computed(() => message.value.trim())
const trimmedEmail = computed(() => email.value.trim())
const characterCount = computed(() => trimmedMessage.value.length)
const isEmailInvalid = computed(() => Boolean(trimmedEmail.value)
  && (trimmedEmail.value.length > 254 || !emailPattern.test(trimmedEmail.value)))
const validationMessage = computed(() => {
  if (isPreparing.value) return copy.value.processing
  if (!characterCount.value) return copy.value.missingMessage
  if (characterCount.value > maxMessageLength) return copy.value.longMessage(maxMessageLength)
  if (isEmailInvalid.value) return copy.value.invalidEmail
  return ''
})

useHead(() => ({
  title: `${copy.value.title} | Cubegin`,
  htmlAttrs: { lang: props.language },
}))

function dismissValidationNotice() {
  clearTimeout(noticeTimer)
  validationNotice.value = undefined
}

function saveEmail(address: string) {
  try {
    if (address) localStorage.setItem(savedEmailKey, address)
    else localStorage.removeItem(savedEmailKey)
  } catch {
    // Feedback remains available when browser storage is blocked.
  }
}

function clearEmail() {
  email.value = ''
  saveEmail('')
  document.getElementById('feedback-email')?.focus()
}

function clearMessage() {
  message.value = ''
  document.getElementById('feedback-message')?.focus()
}

onMounted(() => {
  try {
    email.value = localStorage.getItem(savedEmailKey) ?? ''
  } catch {
    // The reply address is optional.
  }
})
watch(validationMessage, dismissValidationNotice)

async function sendFeedback() {
  if (status.value === 'sending') return
  if (validationMessage.value) {
    dismissValidationNotice()
    validationNotice.value = { message: validationMessage.value, shownAt: Date.now() }
    noticeTimer = setTimeout(dismissValidationNotice, 3000)
    return
  }

  const submittedMessage = trimmedMessage.value
  const submittedEmail = trimmedEmail.value
  if (attempt?.message !== submittedMessage || attempt?.email !== submittedEmail || attempt?.screenshots !== screenshots.value) {
    attempt = { message: submittedMessage, email: submittedEmail, requestId: crypto.randomUUID(), screenshots: screenshots.value }
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
    email.value = submittedEmail
    saveEmail(submittedEmail)
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
  dismissValidationNotice()
  for (const screenshot of screenshots.value) URL.revokeObjectURL(screenshot.preview)
})
</script>

<template>
  <main class="site-frame policy-page">
    <h1>{{ copy.title }}</h1>
    <form class="grid max-w-xl gap-3" novalidate @submit.prevent="sendFeedback">
      <Card class="gap-0 overflow-hidden rounded-2xl py-0">
        <Textarea
          id="feedback-message"
          v-model="message"
          required
          rows="5"
          :aria-label="copy.message"
          :aria-invalid="characterCount > maxMessageLength || undefined"
          aria-describedby="feedback-character-count"
          :placeholder="copy.placeholder"
          :readonly="status === 'sending'"
          class="field-sizing-content min-h-32 max-h-64 resize-none rounded-none border-0 px-4 pt-4 shadow-none focus-visible:ring-inset sm:px-5 md:text-base"
        />
        <div class="flex items-end justify-between gap-2 px-4 pb-4 pt-2 sm:px-5">
          <div class="flex min-w-0 flex-1 items-center gap-2">
            <div
              v-for="(screenshot, index) in screenshots"
              :key="screenshot.preview"
              class="relative aspect-square w-17 min-w-0 rounded-md bg-secondary"
            >
              <img :src="screenshot.preview" :alt="copy.screenshotAlt(index)" class="absolute inset-0 size-full rounded-md object-cover" />
              <Button
                type="button" variant="ghost" size="icon"
                class="absolute top-0 right-0 size-11 items-start justify-end rounded-md p-1 hover:bg-transparent"
                :aria-label="copy.removeImage(index)" :disabled="status === 'sending' || isPreparing"
                @click="removeScreenshot(index)"
              >
                <span class="grid size-5 place-items-center rounded-full bg-black/75 text-white">
                  <X aria-hidden="true" class="size-3" />
                </span>
              </Button>
            </div>
            <input
              id="feedback-screenshots"
              ref="screenshotInput"
              type="file"
              accept="image/jpeg,image/png"
              multiple
              :aria-label="copy.screenshots"
              :disabled="isPreparing || status === 'sending' || screenshots.length === maxScreenshots"
              class="sr-only"
              tabindex="-1"
              @change="addScreenshots"
            >
            <Button
              v-if="screenshots.length < maxScreenshots"
              type="button" variant="outline" size="icon"
              class="aspect-square h-auto w-17 min-w-0 shrink border-dashed border-primary/65 bg-primary/5 text-primary shadow-none hover:bg-primary/10 hover:text-primary"
              :aria-label="isPreparing ? copy.processing : copy.addScreenshots"
              :disabled="isPreparing || status === 'sending'"
              @click="screenshotInput?.click()"
            >
              <LoaderCircle v-if="isPreparing" aria-hidden="true" class="size-5 motion-safe:animate-spin" />
              <Plus v-else aria-hidden="true" class="size-5" />
            </Button>
          </div>
          <div class="grid shrink-0 justify-items-end">
            <Button
              v-if="message"
              type="button" variant="ghost" size="icon"
              class="size-11 rounded-full text-muted-foreground"
              :aria-label="copy.clearMessage" :disabled="status === 'sending'"
              @click="clearMessage"
            >
              <CircleX aria-hidden="true" />
            </Button>
            <span
              id="feedback-character-count"
              class="text-xs whitespace-nowrap tabular-nums"
              :class="characterCount > maxMessageLength ? 'text-destructive' : 'text-muted-foreground'"
            >
              <span aria-hidden="true">{{ characterCount }} / {{ maxMessageLength }}</span>
              <span class="sr-only">{{ copy.characterCount(characterCount, maxMessageLength) }}</span>
            </span>
          </div>
        </div>
        <div class="mx-4 border-t border-border sm:mx-5" />
        <div class="relative flex items-center">
          <Input
            id="feedback-email"
            v-model="email"
            type="email"
            autocomplete="email"
            :aria-label="copy.email"
            :aria-invalid="isEmailInvalid || undefined"
            aria-describedby="feedback-email-help"
            :placeholder="copy.email"
            :readonly="status === 'sending'"
            class="h-12 rounded-none border-0 px-4 shadow-none focus-visible:ring-inset sm:px-5 md:text-base"
            :class="{ 'pr-14 sm:pr-15': email }"
          />
          <Button
            v-if="email"
            type="button" variant="ghost" size="icon"
            class="absolute right-1 size-11 rounded-full text-muted-foreground sm:right-2"
            :aria-label="copy.clearEmail" :disabled="status === 'sending'"
            @click="clearEmail"
          >
            <CircleX aria-hidden="true" />
          </Button>
        </div>
      </Card>
      <div class="px-4 text-sm text-muted-foreground sm:px-5">
        <p id="feedback-email-help">{{ copy.emailHelp }}</p>
        <p v-if="screenshotError" role="alert" class="mt-1 text-destructive">{{ copy[screenshotError] }}</p>
      </div>
      <div hidden>
        <label for="feedback-website">Website</label>
        <input id="feedback-website" v-model="website" type="text" tabindex="-1" autocomplete="off">
      </div>
      <Button
        type="submit" size="lg"
        class="h-12 w-full rounded-full"
        :variant="validationMessage ? 'secondary' : 'default'"
        :aria-describedby="validationNotice ? 'feedback-validation' : undefined"
        :disabled="status === 'sending'"
      >
        <LoaderCircle v-if="status === 'sending'" aria-hidden="true" class="motion-safe:animate-spin" />
        <Send v-else aria-hidden="true" />
        {{ status === 'sending' ? copy.sending : copy.send }}
      </Button>
      <p v-if="status === 'sent'" role="status" class="px-4 text-sm sm:px-5">{{ copy.sent }}</p>
      <p v-if="status === 'failed'" role="alert" class="px-4 text-sm text-destructive sm:px-5">{{ copy.failed }}</p>
      <p v-if="status === 'limited'" role="alert" class="px-4 text-sm text-destructive sm:px-5">{{ copy.limited }}</p>
      <Button v-if="reviewURL" as-child variant="outline" class="h-11 justify-between rounded-xl border-border px-4 sm:px-5">
        <a :href="reviewURL">
          {{ copy.review }}
          <ArrowUpRight aria-hidden="true" />
        </a>
      </Button>
      <NuxtLink :to="copy.privacyPath" class="w-fit text-sm text-primary underline underline-offset-4">
        {{ copy.privacy }}
      </NuxtLink>
    </form>
    <div class="pointer-events-none fixed inset-x-4 bottom-[max(1rem,env(safe-area-inset-bottom))] z-10 flex justify-center">
      <Card
        v-if="validationNotice"
        :key="validationNotice.shownAt"
        id="feedback-validation"
        role="alert"
        class="flex-row items-center gap-2 rounded-xl bg-foreground px-4 py-3 text-sm font-medium text-background"
      >
        <Info aria-hidden="true" class="size-4 shrink-0" />
        {{ validationNotice.message }}
      </Card>
    </div>
  </main>
</template>
