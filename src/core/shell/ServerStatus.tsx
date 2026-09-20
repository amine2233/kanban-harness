import {
  apiBaseUrl,
  selectLiveStatus,
  selectServerUrl,
  useAppSelector,
  useHealthQuery,
} from '@mvp/state'
import { cx } from '@mvp/design-system'

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
