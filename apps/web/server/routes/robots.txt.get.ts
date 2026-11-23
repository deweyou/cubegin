import { siteOrigin } from '#shared/utils/site-seo'

const restrictedCrawlers = [
  'GPTBot',
  'ClaudeBot',
  'CCBot',
  'Google-Extended',
  'Applebot-Extended',
]

export default defineEventHandler((event) => {
  const origin = siteOrigin(useRuntimeConfig(event).public.siteUrl)
  setResponseHeader(event, 'Content-Type', 'text/plain; charset=utf-8')
  return [
    'User-agent: *\nDisallow: /api/',
    restrictedCrawlers.map(agent => `User-agent: ${agent}\nDisallow: /`).join('\n\n'),
    ...(origin ? [`Sitemap: ${new URL('/sitemap.xml', origin).href}`] : []),
    '',
  ].join('\n\n')
})
