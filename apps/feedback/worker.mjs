export { FeedbackDeliveryLimit } from './delivery-limit.mjs'

const maxImages = 3
const maxImageBytes = 1_000_000
const maxTextBytes = 28_000
const emailPattern = /^[^\s@<>,;\p{Cc}]+@[^\s@<>,;\p{Cc}]+\.[^\s@<>,;\p{Cc}]+$/u
const uuidPattern = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i

function reply(status, headers, code, retryAfter) {
  return Response.json(code ? { code } : { sent: true }, {
    status,
    headers: {
      ...headers,
      'Cache-Control': 'no-store',
      ...(retryAfter ? { 'Retry-After': String(retryAfter) } : {}),
    },
  })
}

async function feedbackFields(request, contentType) {
  const multipart = contentType.startsWith('multipart/form-data;')
  const limit = multipart ? maxImages * maxImageBytes + maxTextBytes : maxTextBytes
  if (Number(request.headers.get('Content-Length')) > limit) throw new RangeError()

  let receivedBytes = 0
  const stream = request.body?.pipeThrough(new TransformStream({
    transform(chunk, controller) {
      receivedBytes += chunk.byteLength
      if (receivedBytes > limit) throw new RangeError()
      controller.enqueue(chunk)
    },
  }))
  const body = new Response(stream, { headers: { 'Content-Type': contentType } })
  if (multipart) {
    const data = await body.formData()
    return {
      message: data.get('message'),
      email: data.get('email'),
      requestId: data.get('requestId'),
      website: data.get('website'),
      images: data.getAll('images'),
    }
  }
  // Preserve text-only submissions from clients released before image support.
  const data = await body.json()
  return { ...data, images: [] }
}

function imageType(bytes, end) {
  if (bytes.length >= 4 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff
    && end.at(-2) === 0xff && end.at(-1) === 0xd9) {
    return 'image/jpeg'
  }
  if (bytes.length >= 24 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47
    && bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
    && bytes[12] === 0x49 && bytes[13] === 0x48 && bytes[14] === 0x44 && bytes[15] === 0x52
    && end.at(-8) === 0x49 && end.at(-7) === 0x45 && end.at(-6) === 0x4e && end.at(-5) === 0x44) {
    return 'image/png'
  }
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin')
    const allowedOrigins = env.FEEDBACK_ORIGINS.split(',').map(value => value.trim())
    const headers = { Vary: 'Origin' }
    if (new URL(request.url).pathname !== '/api/feedback') return reply(404, headers, 'not_found')
    if (origin && !allowedOrigins.includes(origin)) return reply(403, headers, 'origin_not_allowed')
    if (origin) headers['Access-Control-Allow-Origin'] = origin

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          ...headers,
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
          'Access-Control-Max-Age': '600',
        },
      })
    }
    if (request.method !== 'POST') return reply(405, { ...headers, Allow: 'POST, OPTIONS' }, 'method_not_allowed')

    const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown'
    if (!(await env.IP_LIMIT.limit({ key: ip })).success) return reply(429, headers, 'rate_limited', 60)
    const contentType = request.headers.get('Content-Type') ?? ''
    if (!/^application\/json(?:;|$)/i.test(contentType) && !contentType.startsWith('multipart/form-data;')) {
      return reply(415, headers, 'unsupported_format')
    }

    let fields
    try {
      fields = await feedbackFields(request, contentType)
    } catch (error) {
      return error instanceof RangeError
        ? reply(413, headers, 'request_too_large')
        : reply(400, headers, 'invalid_request')
    }
    const message = typeof fields.message === 'string' ? fields.message.trim() : ''
    const email = typeof fields.email === 'string' ? fields.email.trim() : ''
    if (!message || message.length > 4000 || email.length > 254 || (email && !emailPattern.test(email))
      || typeof fields.requestId !== 'string' || !uuidPattern.test(fields.requestId)) {
      return reply(400, headers, 'invalid_fields')
    }
    if (fields.website) return reply(200, headers)
    if (fields.images.length > maxImages) return reply(413, headers, 'too_many_images')

    const images = []
    for (const file of fields.images) {
      if (!(file instanceof File) || !file.size) return reply(400, headers, 'invalid_image')
      if (file.size > maxImageBytes) return reply(413, headers, 'image_too_large')
      const [start, end] = await Promise.all([file.slice(0, 24).arrayBuffer(), file.slice(-12).arrayBuffer()])
      const type = imageType(new Uint8Array(start), new Uint8Array(end))
      if (!type || file.type !== type) return reply(400, headers, 'invalid_image')
      images.push({ file, type })
    }

    const requestId = fields.requestId.toLowerCase()
    const deliveries = env.DELIVERY_LIMIT.getByName('feedback')
    const reservation = await deliveries.reserve(requestId)
    if (reservation === 'sent') return reply(200, headers)
    if (reservation === 'pending') return reply(409, headers, 'delivery_pending')
    if (typeof reservation === 'object') return reply(429, headers, 'rate_limited', reservation.retryAfter)

    let attachments
    try {
      attachments = await Promise.all(images.map(async ({ file, type }, index) => ({
        filename: `screenshot-${index + 1}.${type === 'image/png' ? 'png' : 'jpg'}`,
        type,
        content: new Uint8Array(await file.arrayBuffer()).toBase64(),
        disposition: 'attachment',
      })))
    } catch {
      await deliveries.finish(requestId, 'failed')
      return reply(502, headers, 'delivery_failed')
    }

    try {
      await env.EMAIL.send({
        from: env.FEEDBACK_FROM,
        to: env.FEEDBACK_TO,
        subject: 'Cubegin feedback',
        text: message,
        ...(email ? { replyTo: email } : {}),
        attachments,
      })
    } catch (error) {
      // Validation and throttling errors reject the email before delivery. Keep an
      // ambiguous outcome reserved so retrying a lost response cannot duplicate it.
      if (typeof error?.code === 'string' && /^(E_(SENDER|RECIPIENT|FIELD|INVALID|TOO_|RATE_LIMIT|EMAIL_SENDING_NOT_READY))/.test(error.code)) {
        await deliveries.finish(requestId, 'failed')
      }
      return reply(502, headers, 'delivery_failed')
    }
    await deliveries.finish(requestId, 'sent')
    return reply(200, headers)
  },
}
