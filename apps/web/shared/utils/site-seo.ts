export const localizedPaths = {
  home: { 'zh-Hans': '/', en: '/en/' },
  privacy: { 'zh-Hans': '/privacy/', en: '/en/privacy/' },
  playground: { 'zh-Hans': '/playground/', en: '/en/playground/' },
  feedback: { 'zh-Hans': '/feedback/', en: '/en/feedback/' },
} as const

export type SitePage = keyof typeof localizedPaths
export type SiteLanguage = keyof typeof localizedPaths.home

export const indexablePages = ['home', 'privacy', 'playground'] as const

export function siteOrigin(value: string) {
  try {
    const url = new URL(value)
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password
      || url.pathname !== '/' || url.search || url.hash) return undefined
    return url.origin
  } catch {
    return undefined
  }
}
