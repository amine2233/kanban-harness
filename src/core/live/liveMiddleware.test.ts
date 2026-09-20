import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest'
import { createStore } from '@/app/store'
import { setServerUrl } from '@/core/settings/settingsSlice'
import { projectsApi } from '@/plugins/projects/api/projectsApi'
import { stubApi } from '@/test/fakeApi'
import { selectLiveEventCount, selectLiveStatus, startLive, stopLive } from './liveSlice'

/** Records every socket the middleware opens and lets tests drive it. */
class FakeWebSocket {
  static instances: FakeWebSocket[] = []
  onopen: (() => void) | null = null
  onmessage: ((event: { data: string }) => void) | null = null
  onclose: (() => void) | null = null
  onerror: (() => void) | null = null
  closed = false
  url: string

  constructor(url: string) {
    this.url = url
    FakeWebSocket.instances.push(this)
  }

  close() {
    if (this.closed) return
    this.closed = true
    this.onclose?.()
  }

  open() {
    this.onopen?.()
  }

  receive(data: object) {
    this.onmessage?.({ data: JSON.stringify(data) })
  }

  static get latest(): FakeWebSocket {
    const last = FakeWebSocket.instances[FakeWebSocket.instances.length - 1]
    if (!last) throw new Error('no socket opened')
    return last
  }
}

beforeEach(() => {
  FakeWebSocket.instances = []
  vi.stubGlobal('WebSocket', FakeWebSocket)
  vi.useFakeTimers()
})

afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllGlobals()
  localStorage.clear()
})

describe('liveMiddleware', () => {
  test('connects to /api/events on start and tracks status', () => {
    const store = createStore()
    expect(selectLiveStatus(store.getState())).toBe('idle')
    store.dispatch(startLive())
    expect(FakeWebSocket.latest.url).toBe(`ws://localhost:3000/api/events`)
    expect(selectLiveStatus(store.getState())).toBe('connecting')
    FakeWebSocket.latest.open()
    expect(selectLiveStatus(store.getState())).toBe('open')
    store.dispatch(stopLive())
    expect(FakeWebSocket.latest.closed).toBe(true)
    expect(selectLiveStatus(store.getState())).toBe('closed')
  })

  test('an event refetches the caches it names', async () => {
    let served = 0
    stubApi({
      'GET /api/projects': () => {
        served += 1
        return { body: [] }
      },
    })
    const store = createStore()
    store.dispatch(startLive())
    FakeWebSocket.latest.open()
    const subscription = store.dispatch(projectsApi.endpoints.listProjects.initiate())
    await vi.runAllTimersAsync()
    expect(served).toBe(1)

    FakeWebSocket.latest.receive({ kind: 'settings_changed' })
    await vi.runAllTimersAsync()
    expect(served).toBe(1)

    FakeWebSocket.latest.receive({ kind: 'projects_changed' })
    await vi.runAllTimersAsync()
    expect(served).toBe(2)
    expect(selectLiveEventCount(store.getState())).toBe(2)
    subscription.unsubscribe()
    store.dispatch(stopLive())
  })

  test('reconnects with backoff after the socket closes', () => {
    const store = createStore()
    store.dispatch(startLive())
    const first = FakeWebSocket.latest
    first.open()
    first.close()
    expect(selectLiveStatus(store.getState())).toBe('closed')
    expect(FakeWebSocket.instances).toHaveLength(1)
    vi.advanceTimersByTime(1_000)
    expect(FakeWebSocket.instances).toHaveLength(2)
    FakeWebSocket.latest.close()
    vi.advanceTimersByTime(1_000)
    expect(FakeWebSocket.instances).toHaveLength(2)
    vi.advanceTimersByTime(1_000)
    expect(FakeWebSocket.instances).toHaveLength(3)
    store.dispatch(stopLive())
    vi.advanceTimersByTime(60_000)
    expect(FakeWebSocket.instances).toHaveLength(3)
  })

  test('follows a server url change', () => {
    const store = createStore()
    store.dispatch(startLive())
    FakeWebSocket.latest.open()
    store.dispatch(setServerUrl('http://10.0.0.2:5175'))
    expect(FakeWebSocket.instances).toHaveLength(2)
    expect(FakeWebSocket.instances[0]?.closed).toBe(true)
    expect(FakeWebSocket.latest.url).toBe('ws://10.0.0.2:5175/api/events')
    store.dispatch(stopLive())
  })
})
