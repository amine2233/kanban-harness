import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Provider } from 'react-redux'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { createStore } from '@/app/store'
import { selectServerUrl, SETTINGS_STORAGE_KEY } from '@/core/settings/settingsSlice'
import { SettingsPage } from './SettingsPage'

afterEach(() => {
  localStorage.clear()
  vi.unstubAllGlobals()
})

function renderPage() {
  const store = createStore()
  render(
    <Provider store={store}>
      <SettingsPage />
    </Provider>,
  )
  return store
}

describe('SettingsPage', () => {
  test('saves a normalised server url to the store and localStorage', async () => {
    const store = renderPage()
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled()
    await userEvent.type(screen.getByLabelText('Server URL'), 'http://127.0.0.1:5175/')
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect(selectServerUrl(store.getState())).toBe('http://127.0.0.1:5175')
    expect(JSON.parse(localStorage.getItem(SETTINGS_STORAGE_KEY) ?? '{}')).toEqual({
      serverUrl: 'http://127.0.0.1:5175',
    })
    expect(screen.getByText('Saved')).toBeInTheDocument()
    expect(screen.getByText('API requests now go to http://127.0.0.1:5175/api')).toBeInTheDocument()
  })

  test('rejects invalid urls and resets to default', async () => {
    localStorage.setItem(SETTINGS_STORAGE_KEY, JSON.stringify({ serverUrl: 'http://old:1' }))
    const store = renderPage()
    expect(screen.getByLabelText('Server URL')).toHaveValue('http://old:1')
    await userEvent.clear(screen.getByLabelText('Server URL'))
    await userEvent.type(screen.getByLabelText('Server URL'), 'nope')
    expect(
      screen.getByText('Enter an absolute http(s) URL, or leave it empty.'),
    ).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled()
    await userEvent.click(screen.getByRole('button', { name: 'Reset to default' }))
    expect(selectServerUrl(store.getState())).toBe('')
    expect(screen.getByLabelText('Server URL')).toHaveValue('')
  })

  test('test connection reports reachable and unreachable servers', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response('{"status":"ok"}', { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)
    renderPage()
    await userEvent.type(screen.getByLabelText('Server URL'), 'http://127.0.0.1:5175')
    await userEvent.click(screen.getByRole('button', { name: 'Test connection' }))
    expect(await screen.findByText('Server reachable')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith('http://127.0.0.1:5175/api/health')

    fetchMock.mockRejectedValueOnce(new TypeError('Failed to fetch'))
    await userEvent.click(screen.getByRole('button', { name: 'Test connection' }))
    expect(await screen.findByText('Server unreachable')).toBeInTheDocument()
  })
})
