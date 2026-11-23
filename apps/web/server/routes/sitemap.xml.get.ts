import { indexablePages, localizedPaths, siteOrigin } from '#shared/utils/site-seo'

export default defineEventHandler((event) => {
  const origin = siteOrigin(useRuntimeConfig(event).public.siteUrl)
  if (!origin) throw createError({ statusCode: 404, statusMessage: 'Sitemap unavailable' })

  const urls = indexablePages.flatMap(page => Object.values(localizedPaths[page]))
  const entries = urls.map(path => {
    const location = new URL(path, origin).href.replaceAll('&', '&amp;')
    return `  <url><loc>${location}</loc></url>`
  })
  setResponseHeader(event, 'Content-Type', 'application/xml; charset=utf-8')
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...entries,
    '</urlset>',
    '',
  ].join('\n')
})
