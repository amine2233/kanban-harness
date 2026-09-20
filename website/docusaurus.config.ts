import { themes as prismThemes } from 'prism-react-renderer'
import type { Config } from '@docusaurus/types'
import type * as Preset from '@docusaurus/preset-classic'

const config: Config = {
  title: 'MVP Dashboard',
  tagline:
    'Kanban boards for your projects, with an AI that drafts tickets — server, CLI, MCP and web.',
  favicon: 'img/favicon.ico',
  future: { v4: true },
  url: 'https://amine2233.github.io',
  baseUrl: '/',
  organizationName: 'amine2233',
  projectName: 'kanban-harness',
  onBrokenLinks: 'throw',
  markdown: { mermaid: true, hooks: { onBrokenMarkdownLinks: 'throw' } },
  themes: ['@docusaurus/theme-mermaid'],
  i18n: { defaultLocale: 'en', locales: ['en'] },
  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/amine2233/kanban-harness/tree/main/website/',
        },
        blog: false,
        theme: { customCss: './src/css/custom.css' },
      } satisfies Preset.Options,
    ],
  ],
  themeConfig: {
    colorMode: { respectPrefersColorScheme: true },
    navbar: {
      title: 'MVP Dashboard',
      items: [
        { type: 'docSidebar', sidebarId: 'docs', position: 'left', label: 'Docs' },
        { href: 'https://github.com/amine2233/kanban-harness', label: 'GitHub', position: 'right' },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Use',
          items: [
            { label: 'Web app', to: '/web/features' },
            { label: 'CLI', to: '/cli' },
            { label: 'MCP', to: '/mcp' },
          ],
        },
        {
          title: 'Build',
          items: [
            { label: 'Architecture', to: '/architecture' },
            { label: 'HTTP API', to: '/server/api' },
            { label: 'Conceptions', to: '/conceptions/ai-agents' },
          ],
        },
      ],
      copyright: 'MVP Dashboard documentation.',
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['bash', 'json', 'yaml', 'swift'],
    },
  } satisfies Preset.ThemeConfig,
}

export default config
