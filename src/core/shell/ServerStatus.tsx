import { useAppSelector } from '@/app/hooks'
import { selectLiveStatus } from '@/core/live/liveSlice'
import { apiBaseUrl, selectServerUrl } from '@/core/settings/settingsSlice'
import { cx } from '@mvp/design-system'
import { useHealthQuery } from './healthApi'

/** Live API reachability, polled; shows which server this browser talks to. */
export function ServerStatus() {
  const serverUrl = useAppSelector(selectServerUrl)
  const live = useAppSelector(selectLiveStatus)
  const { isSuccess, isError, isLoading } = useHealthQuery(undefined, { pollingInterval: 30_000 })
  const state =
    live === 'open'
      ? 'live'
      : isLoading
        ? 'checking'
        : isSuccess
          ? 'online'
          : isError
            ? 'offline'
            : 'checking'
  const label =
    state === 'live'
      ? 'Live'
      : state === 'online'
        ? 'Connected'
        : state === 'offline'
          ? 'Server unreachable'
          : 'Connecting…'
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
