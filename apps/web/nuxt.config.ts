import tailwindcss from '@tailwindcss/vite'
import { initialThemeScript } from './app/lib/theme'

export default defineNuxtConfig({
  compatibilityDate: '2026-11-20',
  telemetry: false,
  runtimeConfig: {
    public: {
      appStoreId: '',
      feedbackEndpoint: '',
      siteUrl: '',
    },
  },
  css: ['~/assets/css/main.css'],
  app: {
    head: {
      script: [{ key: 'cubegin-theme', innerHTML: initialThemeScript }],
      link: [
        { rel: 'icon', type: 'image/png', sizes: '48x48', href: '/favicon.png' },
        { rel: 'icon', type: 'image/svg+xml', sizes: 'any', href: '/favicon.svg' },
        { rel: 'apple-touch-icon', sizes: '180x180', href: '/apple-touch-icon.png' },
      ],
    },
  },
  modules: ['shadcn-nuxt'],
  shadcn: {
    componentDir: './app/components/ui',
  },
  vite: {
    plugins: [tailwindcss()],
  },
  nitro: {
    prerender: { failOnError: true },
  },
  hooks: {
    'nitro:config'(config) {
      if (!config.static) return

      config.prerender ??= {}
      config.prerender.routes ??= []
      config.prerender.routes.push('/', '/en', '/privacy', '/en/privacy', '/feedback', '/en/feedback', '/robots.txt')
    },
  },
})
