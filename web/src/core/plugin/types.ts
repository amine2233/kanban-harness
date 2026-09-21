import type { ComponentType } from 'react'
import type { RouteObject } from 'react-router'
import type { IconName } from '@mvp/design-system'

export interface NavItem {
  label: string
  to: string
  icon: IconName
}

export interface DashboardPlugin {
  id: string
  name: string
  nav: NavItem[]
  routes: RouteObject[]
  /** Optional dynamic sidebar section rendered below the static nav items. */
  sidebar?: ComponentType
}
