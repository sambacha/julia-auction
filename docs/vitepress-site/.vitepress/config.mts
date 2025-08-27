import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Julia Auction System',
  description: 'Advanced auction mechanisms for DeFi',
  base: '/',
  ignoreDeadLinks: true,
  themeConfig: {
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Guide', link: '/quickstart' },
      { text: 'API', link: '/api/augmented' },
      { text: 'GitHub', link: 'https://github.com/julia-auction/julia-auction' }
    ],
    sidebar: [
      {
        text: 'Getting Started',
        items: [
          { text: 'Introduction', link: '/' },
          { text: 'Installation', link: '/installation' },
          { text: 'Quick Start', link: '/quickstart' }
        ]
      },
      {
        text: 'Guides',
        items: [
          { text: 'Core Concepts', link: '/guides/concepts' },
          { text: 'Quick Start Guide', link: '/guides/quickstart' },
          { text: 'Installation Guide', link: '/guides/installation' },
          { text: 'Development', link: '/guides/development' },
          { text: 'Contributing', link: '/guides/contributing' },
          { text: 'Production Status', link: '/guides/production_status' }
        ]
      },
      {
        text: 'Theory',
        items: [
          { text: 'Overview', link: '/theory/overview' },
          { text: 'Auction Theory', link: '/theory' },
          { text: 'Elastic Supply', link: '/elastic-supply' },
          { text: 'Elastic Supply (Theory)', link: '/theory/elastic_supply' },
          { text: 'Augmented Mechanisms', link: '/theory/augmented_uniform' },
          { text: 'Bid Shading', link: '/theory/bid_shading' },
          { text: 'Phantom Auctions', link: '/theory/phantom_auctions' },
          { text: 'MEV Protection', link: '/theory/mev' },
          { text: 'Academic References', link: '/theory/academic' },
          { text: 'References', link: '/theory/references' }
        ]
      },
      {
        text: 'API Reference',
        items: [
          { text: 'Augmented Auctions', link: '/api/augmented' },
          { text: 'Settlement', link: '/api/settlement' },
          { text: 'Phantom Auctions', link: '/api/phantom' }
        ]
      },
      {
        text: 'Examples',
        items: [
          { text: 'Basic Usage', link: '/examples/basic' },
          { text: 'Advanced Patterns', link: '/examples/advanced' },
          { text: 'Performance', link: '/examples/performance' }
        ]
      }
    ],
    search: {
      provider: 'local'
    },
    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2025 Julia Auction System'
    }
  }
})