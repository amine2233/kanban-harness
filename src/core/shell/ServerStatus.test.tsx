import { render, screen } from '@testing-library/react'
import { Provider } from 'react-redux'
import { afterEach, expect, test, vi } from 'vitest'
import { createStore } from '@/app/store'
import { stubApi } from '@/test/fakeApi'
import { ServerStatus } from './ServerStatus'

afterEach(() => {
  vi.unstubAllGlobals()
})

test('reports connected when /api/health answers and unreachable otherwise', async () => {
  stubApi({ 'GET /api/health': () => ({ body: { status: 'ok' } }) })
  const { unmount } = render(
    <Provider store={createStore()}>
      <ServerStatus />
    </Provider>,
  )
  expect(await screen.findByRole('status', { name: /Connected/ })).toHaveClass('ds-status--online')
  unmount()

  vi.unstubAllGlobals()
  stubApi({})
  render(
    <Provider store={createStore()}>
      <ServerStatus />
    </Provider>,
  )
  expect(await screen.findByRole('status', { name: /Server unreachable/ })).toHaveClass(
    'ds-status--offline',
  )
})
