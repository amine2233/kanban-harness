import type { ComponentType } from 'react'
import type { RouteObject } from 'react-router'
import type { DashboardPlugin, NavItem } from './types'

export interface PluginRegistry {
  plugins: readonly DashboardPlugin[]
  nav: NavItem[]
  routes: RouteObject[]
  sidebarSections: ComponentType[]
}

export function buildRegistry(plugins: readonly DashboardPlugin[]): PluginRegistry {
  const seen = new Set<string>()
  for (const plugin of plugins) {
    if (seen.has(plugin.id)) throw new Error(`Duplicate plugin id: ${plugin.id}`)
    seen.add(plugin.id)
  }
  return {
    plugins,
    nav: plugins.flatMap((p) => p.nav),
    routes: plugins.flatMap((p) => p.routes),
    sidebarSections: plugins.flatMap((p) => (p.sidebar ? [p.sidebar] : [])),
  }
}
