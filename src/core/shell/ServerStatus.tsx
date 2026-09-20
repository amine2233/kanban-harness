import { useAppSelector } from '@/app/hooks'
import { apiBaseUrl, selectServerUrl } from '@/core/settings/settingsSlice'
import { cx } from '@/design-system'
import { useHealthQuery } from './healthApi'

/** Live API reachability, polled; shows which server this browser talks to. */
export function ServerStatus() {
  const serverUrl = useAppSelector(selectServerUrl)
  const { isSuccess, isError, isLoading } = useHealthQuery(undefined, { pollingInterval: 30_000 })
  const state = isLoading ? 'checking' : isSuccess ? 'online' : isError ? 'offline' : 'checking'
  const label =
    state === 'online' ? 'Connected' : state === 'offline' ? 'Server unreachable' : 'Connecting…'
  return (
    <span
      className={cx('ds-status', `ds-status--${state}`)}
      role="status"
      title={apiBaseUrl(serverUrl)}
      aria-label={`${label} (${apiBaseUrl(serverUrl)})`}
    >
      <span className="ds-status__dot" />
      {label}
    </span>
  )
}
