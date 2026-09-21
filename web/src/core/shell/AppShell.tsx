import { Outlet } from 'react-router'
import { useTheme } from '@/core/settings/useTheme'
import type { PluginRegistry } from '@/core/plugin/registry'
import { Sidebar } from './Sidebar'
import { TopBar } from './TopBar'
import { selectSidebarCollapsed, useAppSelector } from '@mvp/state'
import { cx } from '@mvp/design-system'

export function AppShell({ title, registry }: { title: string; registry: PluginRegistry }) {
  const collapsed = useAppSelector(selectSidebarCollapsed)
  useTheme()
  return (
    <div className={cx('ds-shell', collapsed && 'ds-shell--collapsed')}>
      <TopBar title={title} />
      <Sidebar items={registry.nav} sections={registry.sidebarSections} />
      <main className="ds-main">
        <Outlet />
      </main>
    </div>
  )
}
