import type { SidebarsConfig } from '@docusaurus/plugin-content-docs'

const sidebars: SidebarsConfig = {
  docs: [
    'index',
    'getting-started',
    'architecture',
    {
      type: 'category',
      label: 'Web app',
      items: ['web/features', 'web/ai-drafting', 'web/architecture'],
    },
    {
      type: 'category',
      label: 'Server',
      items: ['server/overview', 'server/api', 'server/configuration', 'server/security'],
    },
    'cli',
    'mcp',
    {
      type: 'category',
      label: 'AI',
      items: ['ai/providers', 'ai/streaming-and-cost'],
    },
    {
      type: 'category',
      label: 'Conceptions',
      items: [
        'conceptions/ai-agents',
        'conceptions/mcp-servers',
        'conceptions/huggingface-provider',
        'conceptions/provider-sign-in',
        'conceptions/live-connection',
      ],
    },
  ],
}

export default sidebars
