import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  lang: 'en',
  title: "Electric Next",
  description: "Your data, in sync, wherever you need it.",
  appearance: 'force-dark',
  base: '/',
  cleanUrls: true,
  head: [
    ['link', {
      rel: 'icon',
      type: 'image/svg+xml',
      href: '/img/brand/favicon.svg'
    }]
  ],
  // https://vitepress.dev/reference/default-theme-config
  themeConfig: {
    logo: '/img/brand/logo.svg',
    nav: [
      { text: 'About', link: '/about' },
      { text: 'Product', link: '/product/electric', activeMatch: '/product/' },
      { text: 'Guides', link: '/guides/quickstart', activeMatch: '/guides/'},
      { text: 'API', link: '/api/http', activeMatch: '/api/'},
      { text: 'Examples', link: '/examples/basic', activeMatch: '/examples/'},
    ],
    sidebar: [
      {
        text: 'About',
        items: [
          { text: '<code>electric-next</code>', link: '/about' }
        ]
      },
      {
        text: 'Product',
        items: [
          { text: 'Electric', link: '/product/electric' },
          { text: 'DDN', link: '/product/ddn' },
          { text: 'PGlite', link: '/product/pglite' },
        ]
      },
      {
        text: 'Guides',
        items: [
          { text: 'Quickstart', link: '/guides/quickstart' },
          { text: 'Usage', link: '/guides/usage' },
          { text: 'Deployment', link: '/guides/deployment' },
        ]
      },
      {
        text: 'API',
        items: [
          { text: 'HTTP', link: '/api/http' },
          { text: 'JavaScript', link: '/api/js' },
          { text: 'Connectors', link: '/api/other' }
        ]
      }
    ],
    siteTitle: false,
    socialLinks: [
      { icon: 'discord', link: 'https://discord.electric-sql.com' },
      { icon: 'github', link: 'https://github.com/electric-sql/electric-sql' }
    ]
  }
})
