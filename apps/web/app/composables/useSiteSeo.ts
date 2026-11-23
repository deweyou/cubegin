import { localizedPaths, siteOrigin, type SiteLanguage, type SitePage } from '#shared/utils/site-seo'

export function useSiteSeo(
  page: SitePage,
  language: () => SiteLanguage,
  title: () => string,
  description: () => string,
) {
  const origin = siteOrigin(useRuntimeConfig().public.siteUrl)
  const paths = localizedPaths[page]
  const canonical = computed(() => origin ? new URL(paths[language()], origin).href : undefined)
  const locale = computed(() => language() === 'en' ? 'en_US' : 'zh_CN')
  const shareImage = origin ? new URL('/social-preview.jpg', origin).href : undefined
  const alternateLanguages = ['zh-Hans', 'en', 'x-default'] as const
  if (origin && page === 'home') prerenderRoutes('/sitemap.xml')

  useHead(() => ({
    htmlAttrs: { lang: language() },
    link: canonical.value && origin ? [
      { rel: 'canonical', href: canonical.value },
      ...alternateLanguages.map(hreflang => ({
        rel: 'alternate' as const,
        hreflang,
        href: new URL(paths[hreflang === 'x-default' ? 'zh-Hans' : hreflang], origin).href,
      })),
    ] : [],
    script: origin && page === 'home' && language() === 'zh-Hans' ? [{
      key: 'cubegin-website',
      type: 'application/ld+json',
      textContent: JSON.stringify({
        '@context': 'https://schema.org',
        '@type': 'WebSite',
        name: 'Cubegin',
        url: new URL('/', origin).href,
      }),
    }] : [],
  }))

  useSeoMeta({
    title,
    description,
    robots: page === 'feedback' ? 'noindex, follow' : undefined,
    ogSiteName: 'Cubegin',
    ogType: 'website',
    ogTitle: title,
    ogDescription: description,
    ogLocale: () => locale.value,
    ogUrl: () => canonical.value,
    ogImage: shareImage,
    ogImageAlt: shareImage ? 'Cubegin' : undefined,
    ogImageWidth: shareImage ? 1200 : undefined,
    ogImageHeight: shareImage ? 630 : undefined,
    twitterCard: shareImage ? 'summary_large_image' : 'summary',
  })
}
