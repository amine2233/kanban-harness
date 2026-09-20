import { buildRegistry } from '@/core/plugin/registry'
import { overviewPlugin } from '@/plugins/overview'
import { projectsPlugin } from '@/plugins/projects'
import { settingsPlugin } from '@/plugins/settings'

export const registry = buildRegistry([overviewPlugin, projectsPlugin, settingsPlugin])
