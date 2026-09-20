import { useAppDispatch } from '@/app/hooks'
import { ThemePicker } from '@/core/settings/ThemePicker'
import { Icon } from '@mvp/design-system'
import { ServerStatus } from './ServerStatus'
import { toggleSidebar } from './shellSlice'

export function TopBar({ title }: { title: string }) {
  const dispatch = useAppDispatch()
  return (
    <header className="ds-topbar flex items-center ph3">
      <button
        type="button"
        className="ds-icon-button mr2"
        aria-label="Toggle sidebar"
        onClick={() => {
          dispatch(toggleSidebar())
        }}
      >
        <Icon name="menu" size={18} />
      </button>
      <span className="ds-brand">
        <span className="ds-brand__mark">
          <Icon name="bolt" size={14} />
        </span>
        {title}
      </span>
      <span className="ml-auto flex items-center" style={{ gap: 12 }}>
        <ThemePicker compact />
        <ServerStatus />
      </span>
    </header>
  )
}
