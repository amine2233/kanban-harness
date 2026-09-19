import { Outlet } from 'react-router'
import { useAppSelector } from '@/app/hooks'
import { cx } from '@/design-system'
import type { PluginRegistry } from '@/core/plugin/registry'
import { selectSidebarCollapsed } from './shellSlice'
import { Sidebar } from './Sidebar'
import { TopBar } from './TopBar'

export function AppShell({ title, registry }: { title: string; registry: PluginRegistry }) {
  const collapsed = useAppSelector(selectSidebarCollapsed)
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
