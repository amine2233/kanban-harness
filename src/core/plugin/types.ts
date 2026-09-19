import type { RouteObject } from 'react-router'
import type { IconName } from '@/design-system'

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
}
