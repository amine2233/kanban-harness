import { buildRegistry } from '@/core/plugin/registry'
import { appsPlugin } from '@/plugins/apps'
import { overviewPlugin } from '@/plugins/overview'
import { settingsPlugin } from '@/plugins/settings'

export const registry = buildRegistry([overviewPlugin, appsPlugin, settingsPlugin])
