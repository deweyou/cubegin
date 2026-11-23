const maxMessageLength = 4000
const maxBodyBytes = 28_000
const emailPattern = /^[^\s@<>,;]+@[^\s@<>,;]+\.[^\s@<>,;]+$/
const uuidPattern = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i

export default defineEventHandler(async (event) => {
  const contentType = getRequestHeader(event, 'content-type')?.split(';')[0]?.trim()
  if (contentType !== 'application/json' || getRequestHeader(event, 'sec-fetch-site') === 'cross-site') {
    throw createError({ statusCode: 415, statusMessage: 'Unsupported feedback request' })
  }

  const contentLength = Number(getRequestHeader(event, 'content-length') ?? 0)
  if (contentLength > maxBodyBytes) {
    throw createError({ statusCode: 413, statusMessage: 'Feedback request too large' })
  }
  const rawBody = await readRawBody(event)
  if (rawBody && new TextEncoder().encode(rawBody).byteLength > maxBodyBytes) {
    throw createError({ statusCode: 413, statusMessage: 'Feedback request too large' })
  }

  let body: Record<string, unknown> | null
  try {
    body = JSON.parse(rawBody ?? 'null')
  } catch {
    throw createError({ statusCode: 400, statusMessage: 'Invalid feedback request' })
  }
  const message = typeof body?.message === 'string' ? body.message.trim() : ''
  const email = typeof body?.email === 'string' ? body.email.trim() : ''
  const requestId = body?.requestId
  if (!message || message.length > maxMessageLength || email.length > 254
    || (email && !emailPattern.test(email)) || typeof requestId !== 'string' || !uuidPattern.test(requestId)) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid feedback fields' })
  }
  if (body?.website) return { sent: true }

  const { feedbackResendKey, feedbackFrom, feedbackTo } = useRuntimeConfig(event)
  if (!feedbackResendKey || !feedbackFrom || !feedbackTo) {
    throw createError({ statusCode: 503, statusMessage: 'Feedback delivery is unavailable' })
  }
  try {
    await $fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${feedbackResendKey}`,
        'Idempotency-Key': `cubegin-feedback/${requestId}`,
      },
      body: {
        from: feedbackFrom,
        to: [feedbackTo],
        subject: 'Cubegin feedback',
        text: message,
        ...(email ? { reply_to: email } : {}),
      },
      retry: 0,
      timeout: 8000,
    })
  } catch {
    throw createError({ statusCode: 502, statusMessage: 'Feedback delivery failed' })
  }
  return { sent: true }
})
