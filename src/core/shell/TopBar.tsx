import { useAppDispatch } from '@/app/hooks'
import { Icon } from '@/design-system'
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
      <span className="f3 b">{title}</span>
    </header>
  )
}
