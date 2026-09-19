import { Outlet } from 'react-router'
import { useAppSelector } from '@/app/hooks'
import { cx } from '@/design-system'
import type { NavItem } from '@/core/plugin/types'
import { selectSidebarCollapsed } from './shellSlice'
import { Sidebar } from './Sidebar'
import { TopBar } from './TopBar'

export function AppShell({ title, nav }: { title: string; nav: NavItem[] }) {
  const collapsed = useAppSelector(selectSidebarCollapsed)
  return (
    <div className={cx('ds-shell', collapsed && 'ds-shell--collapsed')}>
      <TopBar title={title} />
      <Sidebar items={nav} />
      <main className="ds-main">
        <Outlet />
      </main>
    </div>
  )
}
