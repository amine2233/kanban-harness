import type { DashboardPlugin } from '@/core/plugin/types'
import { AppsPage } from './AppsPage'

export const appsPlugin: DashboardPlugin = {
  id: 'apps',
  name: 'Apps',
  nav: [{ label: 'Apps', to: '/apps', icon: 'grid' }],
  routes: [{ path: '/apps', element: <AppsPage /> }],
}
