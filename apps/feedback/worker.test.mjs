import assert from 'node:assert/strict'
import test from 'node:test'

const endpoint = new URL(process.env.CUBEGIN_FEEDBACK_TEST_URL ?? 'http://127.0.0.1:4491')
assert.equal(endpoint.protocol, 'http:')
assert.equal(endpoint.hostname, '127.0.0.1')
const explorer = new URL('/cdn-cgi/local/explorer/api/local/email/sending', endpoint)
const api = new URL('/api/feedback', endpoint)
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC', 'base64')

async function send(body, ipSuffix, origin) {
  const headers = new Headers({ 'CF-Connecting-IP': `203.0.113.${ipSuffix}` })
  if (origin) headers.set('Origin', origin)
  if (!(body instanceof FormData)) {
    headers.set('Content-Type', 'application/json')
    body = JSON.stringify(body)
  }
  return fetch(api, { method: 'POST', headers, body })
}

async function inbox() {
  const response = await fetch(explorer)
  assert.equal(response.status, 200)
  const { result } = await response.json()
  return result
}

function upload(files, requestId = crypto.randomUUID()) {
  const body = new FormData()
  body.set('message', 'Screenshot feedback')
  body.set('email', 'reply@example.com')
  body.set('requestId', requestId)
  for (const file of files) body.append('images', file, 'user-supplied-name.png')
  return body
}

test('accepts screenshots, protects the inbox and enforces one shared rolling cap', async () => {
  assert.equal((await inbox()).length, 0, 'Start Wrangler with a fresh local inbox')

  const screenshot = new Blob([png], { type: 'image/png' })
  const origin = 'http://localhost:4489'
  const requestId = crypto.randomUUID()
  const response = await send(upload([screenshot, screenshot, screenshot], requestId), 1, origin)
  assert.equal(response.status, 200)
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), origin)
  assert.deepEqual(await response.json(), { sent: true })
  assert.equal((await send(upload([screenshot, screenshot, screenshot], requestId), 2)).status, 200)
  assert.equal((await send(upload(Array(4).fill(screenshot)), 3)).status, 413)
  assert.equal((await send(upload([new Blob([Buffer.alloc(1_000_001)], { type: 'image/png' })]), 4)).status, 413)
  assert.equal((await send(upload([new Blob(['fake image'], { type: 'image/png' })]), 5)).status, 400)
  assert.equal((await send(upload([screenshot]), 6, 'https://excluded.example')).status, 403)
  assert.equal((await send({ message: '  ', requestId: crypto.randomUUID() }, 7)).status, 400)
  const oversized = await fetch(api, {
    method: 'POST',
    duplex: 'half',
    headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '203.0.113.8' },
    body: new ReadableStream({
      start(controller) {
        controller.enqueue(new Uint8Array(15_000))
        controller.enqueue(new Uint8Array(15_000))
        controller.close()
      },
    }),
  })
  assert.equal(oversized.status, 413)

  const sent = await inbox()
  assert.equal(sent.length, 1, 'Rejected uploads and repeat submissions must not send more mail')
  assert.deepEqual(sent[0].to, ['inbox@example.com'])
  assert.deepEqual(sent[0].attachments.map(attachment => attachment.filename),
    ['screenshot-1.png', 'screenshot-2.png', 'screenshot-3.png'])

  for (let index = 0; index < 5; index += 1) {
    assert.equal((await send({ message: '  ', requestId: crypto.randomUUID() }, 20)).status, 400)
  }
  assert.equal((await send({ message: 'IP limit', requestId: crypto.randomUUID() }, 20)).status, 429)

  const submissions = await Promise.all(Array.from({ length: 31 }, (_, index) =>
    send({ message: 'Text-only feedback', requestId: crypto.randomUUID() }, 50 + index)))
  assert.equal(submissions.filter(response => response.status === 200).length, 29)
  const limited = submissions.filter(response => response.status === 429)
  assert.equal(limited.length, 2)
  assert.ok(limited.every(response => Number(response.headers.get('Retry-After')) > 0))
})
