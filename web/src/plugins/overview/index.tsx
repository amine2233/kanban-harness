import type { DashboardPlugin } from '@/core/plugin/types'
import { OverviewPage } from './OverviewPage'

export const overviewPlugin: DashboardPlugin = {
  id: 'overview',
  name: 'Overview',
  nav: [{ label: 'Overview', to: '/overview', icon: 'home' }],
  routes: [{ path: '/overview', element: <OverviewPage /> }],
}
