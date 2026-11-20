import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  compatibilityDate: '2026-11-20',
  telemetry: false,
  css: ['~/assets/css/main.css'],
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
      config.prerender.routes.push('/', '/en', '/privacy', '/en/privacy')
    },
  },
})
