import { ThemePicker } from '@/core/settings/ThemePicker'
import { ServerStatus } from './ServerStatus'
import { toggleSidebar, useAppDispatch } from '@mvp/state'
import { Icon, Row } from '@mvp/design-system'

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
      <Row as="span" gap="md" className="ml-auto">
        <ThemePicker compact />
        <ServerStatus />
      </Row>
    </header>
  )
}
