import tailwindcss from '@tailwindcss/vite'
import { initialThemeScript } from './app/lib/theme'

export default defineNuxtConfig({
  compatibilityDate: '2026-11-20',
  telemetry: false,
  runtimeConfig: {
    public: {
      appStoreId: '',
      feedbackEndpoint: '',
    },
  },
  css: ['~/assets/css/main.css'],
  app: {
    head: {
      script: [{ key: 'cubegin-theme', innerHTML: initialThemeScript }],
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
      config.prerender.routes.push('/', '/en', '/privacy', '/en/privacy', '/feedback', '/en/feedback')
    },
  },
})
