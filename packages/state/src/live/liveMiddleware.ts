import { isAnyOf, type Middleware } from '@reduxjs/toolkit'
import { baseApi } from '../api/baseApi'
import { apiBaseUrl, resetSettings, setServerUrl, settingsSlice } from '../settings/settingsSlice'
import { eventsUrl, parseChangeEvent, tagsFor } from './events'
import {
  liveClosed,
  liveConnecting,
  liveEventReceived,
  liveOpened,
  startLive,
  stopLive,
} from './liveSlice'

const MIN_BACKOFF_MS = 1_000
const MAX_BACKOFF_MS = 30_000

/**
 * Owns the single WebSocket to `/api/events`: every frame becomes a store
 * action and invalidates the caches it names, so all screens refresh from one
 * source of truth. Reconnects with backoff; follows server URL changes.
 */
export const liveMiddleware: Middleware = (store) => {
  let socket: WebSocket | undefined
  let reconnectTimer: ReturnType<typeof setTimeout> | undefined
  let backoff = MIN_BACKOFF_MS
  let enabled = false

  const settingsOf = (state: unknown) =>
    settingsSlice.selectSlice(state as Parameters<typeof settingsSlice.selectSlice>[0])

  const connect = () => {
    if (!enabled) return
    clearTimeout(reconnectTimer)
    store.dispatch(liveConnecting())
    const ws = new WebSocket(eventsUrl(apiBaseUrl(settingsOf(store.getState()).serverUrl)))
    socket = ws
    ws.onopen = () => {
      backoff = MIN_BACKOFF_MS
      store.dispatch(liveOpened())
    }
    ws.onmessage = (message: MessageEvent<unknown>) => {
      const event = parseChangeEvent(String(message.data))
      if (!event) return
      store.dispatch(liveEventReceived(event))
      const tags = tagsFor(event)
      if (tags.length > 0) store.dispatch(baseApi.util.invalidateTags(tags))
    }
    ws.onclose = () => {
      if (socket !== ws) return
      socket = undefined
      store.dispatch(liveClosed())
      if (!enabled) return
      reconnectTimer = setTimeout(connect, backoff)
      backoff = Math.min(backoff * 2, MAX_BACKOFF_MS)
    }
    ws.onerror = () => {
      ws.close()
    }
  }

  const disconnect = () => {
    clearTimeout(reconnectTimer)
    const ws = socket
    socket = undefined
    ws?.close()
  }

  return (next) => (action) => {
    const result = next(action)
    if (startLive.match(action)) {
      enabled = true
      disconnect()
      connect()
    } else if (stopLive.match(action)) {
      enabled = false
      disconnect()
      store.dispatch(liveClosed())
    } else if (isAnyOf(setServerUrl, resetSettings)(action) && enabled) {
      backoff = MIN_BACKOFF_MS
      disconnect()
      connect()
    }
    return result
  }
}
