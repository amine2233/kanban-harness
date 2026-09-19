import type { DashboardPlugin } from '@/core/plugin/types'
import { SettingsPage } from './SettingsPage'

export const settingsPlugin: DashboardPlugin = {
  id: 'settings',
  name: 'Settings',
  nav: [{ label: 'Settings', to: '/settings', icon: 'settings' }],
  routes: [{ path: '/settings', element: <SettingsPage /> }],
}
