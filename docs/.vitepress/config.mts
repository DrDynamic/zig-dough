import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: "PAZ",
  description: "A modern scripting language for backends",
  themeConfig: {
    // https://vitepress.dev/reference/default-theme-config
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Docs', link: '/docs/introduction' }
    ],

    sidebar: [
      {
        text: 'Docs',
        items: [
          { text: 'Introduction', link: '/docs/introduction' },
          { text: 'Features', link: '/docs/types' }
        ]
      },
      {
        text: 'Standard Librtary',
        items: []
      },

      {
        text: 'Digging Deeper',
        items: []
      },
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/vuejs/vitepress' }
    ]
  }
})
