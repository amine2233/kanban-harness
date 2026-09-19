import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Provider } from 'react-redux'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { createStore } from '@/app/store'
import { stubApi } from '@/test/fakeApi'
import { splitOrigins } from './origins'
import { ServerSettingsCard } from './ServerSettingsCard'

afterEach(() => {
  vi.unstubAllGlobals()
})

test('splitOrigins accepts newlines and commas and drops blanks', () => {
  expect(splitOrigins('http://a\n, http://b ,\n\n')).toEqual(['http://a', 'http://b'])
})

describe('ServerSettingsCard', () => {
  test('loads settings, saves changes through PATCH and reports success', async () => {
    let settings = { default_storage: 'json', cors_origins: [] as string[] }
    const api = stubApi({
      'GET /api/settings': () => ({ body: settings }),
      'PATCH /api/settings': (body) => {
        settings = { ...settings, ...(body as typeof settings) }
        return { body: settings }
      },
    })
    render(
      <Provider store={createStore()}>
        <ServerSettingsCard />
      </Provider>,
    )
    const select = await screen.findByLabelText('Default storage for new projects')
    expect(select).toHaveValue('json')
    expect(screen.getByRole('button', { name: 'Save server settings' })).toBeDisabled()

    await userEvent.selectOptions(select, 'sqlite')
    await userEvent.type(screen.getByLabelText(/Allowed browser origins/), 'http://localhost:5173')
    await userEvent.click(screen.getByRole('button', { name: 'Save server settings' }))

    expect(await screen.findByText('Saved and applied.')).toBeInTheDocument()
    expect(api.calls.find((c) => c.key === 'PATCH /api/settings')?.body).toEqual({
      default_storage: 'sqlite',
      cors_origins: ['http://localhost:5173'],
    })
    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'Save server settings' })).toBeDisabled()
    })
  })

  test('shows the server validation error', async () => {
    stubApi({
      'GET /api/settings': () => ({ body: { default_storage: 'json', cors_origins: [] } }),
      'PATCH /api/settings': () => ({
        status: 400,
        body: { code: 'VALIDATION_FAILED', message: "invalid origin 'nope'" },
      }),
    })
    render(
      <Provider store={createStore()}>
        <ServerSettingsCard />
      </Provider>,
    )
    await userEvent.type(await screen.findByLabelText(/Allowed browser origins/), 'nope')
    await userEvent.click(screen.getByRole('button', { name: 'Save server settings' }))
    expect(await screen.findByText("invalid origin 'nope'")).toBeInTheDocument()
  })
})
