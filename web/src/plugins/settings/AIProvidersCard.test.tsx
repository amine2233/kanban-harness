import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Provider } from 'react-redux'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { AIProvidersCard } from './AIProvidersCard'
import { type AIConfig, type AIProvider, createStore } from '@mvp/state'
import { stubApi } from '@mvp/state/testing'

afterEach(() => {
  vi.unstubAllGlobals()
})

const claude: AIProvider = {
  id: 'claude',
  kind: 'anthropic',
  name: 'Claude',
  model: 'claude-sonnet-5',
  base_url: null,
  max_tokens: null,
  pricing: null,
  has_api_key: true,
  oauth_client_id: null,
}

function renderCard() {
  render(
    <Provider store={createStore()}>
      <AIProvidersCard />
    </Provider>,
  )
}

describe('AIProvidersCard', () => {
  test('adds a provider with a write-only key', async () => {
    let config: AIConfig = { providers: [], default_provider: null }
    const api = stubApi({
      'GET /api/settings/ai': () => ({ body: config }),
      'PUT /api/settings/ai/providers/claude': (body) => {
        const b = body as { name: string; model: string }
        config = {
          providers: [{ ...claude, name: b.name, model: b.model }],
          default_provider: 'claude',
        }
        return { body: config }
      },
    })
    renderCard()
    expect(await screen.findByText('No provider configured yet.')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Add provider' }))
    const dialog = screen.getByRole('dialog', { name: 'Add AI provider' })
    await userEvent.type(within(dialog).getByLabelText('Id'), 'CLAUDE')
    expect(within(dialog).getByLabelText('Id')).toHaveValue('claude')
    await userEvent.type(within(dialog).getByLabelText('Name'), 'Claude')
    await userEvent.type(within(dialog).getByLabelText('Model'), 'claude-sonnet-5')
    await userEvent.type(within(dialog).getByLabelText('API key'), 'sk-secret')
    await userEvent.type(within(dialog).getByLabelText('Input $/M tokens'), '3')
    await userEvent.type(within(dialog).getByLabelText('Output $/M tokens'), '15')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Add' }))

    expect(await screen.findByRole('listitem', { name: 'Claude' })).toBeInTheDocument()
    expect(screen.getByText('default')).toBeInTheDocument()
    expect(screen.getByText('key set')).toBeInTheDocument()
    expect(api.calls.find((c) => c.key === 'PUT /api/settings/ai/providers/claude')?.body).toEqual({
      kind: 'anthropic',
      name: 'Claude',
      model: 'claude-sonnet-5',
      base_url: null,
      max_tokens: null,
      pricing: { input_per_million: 3, output_per_million: 15 },
      api_key: 'sk-secret',
    })
  })

  test('editing without touching the key omits api_key; clearing sends an empty key', async () => {
    let config: AIConfig = { providers: [claude], default_provider: 'claude' }
    const api = stubApi({
      'GET /api/settings/ai': () => ({ body: config }),
      'PUT /api/settings/ai/providers/claude': (body) => {
        const b = body as { name: string; api_key?: string }
        config = {
          ...config,
          providers: [{ ...claude, name: b.name, has_api_key: b.api_key !== '' }],
        }
        return { body: config }
      },
    })
    renderCard()
    await userEvent.click(await screen.findByRole('button', { name: 'Claude actions' }))
    await userEvent.click(screen.getByRole('menuitem', { name: 'Edit' }))
    const dialog = screen.getByRole('dialog', { name: 'Edit Claude' })
    expect(within(dialog).getByLabelText('Id')).toBeDisabled()
    await userEvent.clear(within(dialog).getByLabelText('Name'))
    await userEvent.type(within(dialog).getByLabelText('Name'), 'Claude Sonnet')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save' }))
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    })
    expect(
      api.calls.find((c) => c.key === 'PUT /api/settings/ai/providers/claude')?.body,
    ).not.toHaveProperty('api_key')

    await userEvent.click(await screen.findByRole('button', { name: 'Claude Sonnet actions' }))
    await userEvent.click(screen.getByRole('menuitem', { name: 'Edit' }))
    await userEvent.click(screen.getByLabelText('Clear the stored key'))
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))
    await waitFor(() => {
      expect(screen.getByText('no key')).toBeInTheDocument()
    })
    expect(
      (
        api.calls.filter((c) => c.key === 'PUT /api/settings/ai/providers/claude')[1]?.body as {
          api_key?: string
        }
      ).api_key,
    ).toBe('')
  })

  test('sets the default and removes a provider after confirmation', async () => {
    const local: AIProvider = {
      ...claude,
      id: 'local',
      kind: 'ollama',
      name: 'Ollama',
      model: 'llama3.2',
      has_api_key: false,
    }
    let config: AIConfig = { providers: [claude, local], default_provider: 'claude' }
    const api = stubApi({
      'GET /api/settings/ai': () => ({ body: config }),
      'PUT /api/settings/ai/default': (body) => {
        config = { ...config, default_provider: (body as { provider_id: string }).provider_id }
        return { body: config }
      },
      'DELETE /api/settings/ai/providers/claude': () => {
        config = { providers: [local], default_provider: 'local' }
        return { body: config }
      },
    })
    renderCard()
    const ollama = await screen.findByRole('listitem', { name: 'Ollama' })
    expect(within(ollama).getByText('no key needed')).toBeInTheDocument()
    await userEvent.click(within(ollama).getByRole('button', { name: 'Ollama actions' }))
    await userEvent.click(screen.getByRole('menuitem', { name: 'Make default' }))
    await waitFor(() => {
      expect(
        within(screen.getByRole('listitem', { name: 'Ollama' })).getByText('default'),
      ).toBeInTheDocument()
    })
    expect(api.calls.find((c) => c.key === 'PUT /api/settings/ai/default')?.body).toEqual({
      provider_id: 'local',
    })

    await userEvent.click(screen.getByRole('button', { name: 'Claude actions' }))
    await userEvent.click(screen.getByRole('menuitem', { name: 'Remove' }))
    await userEvent.click(
      within(screen.getByRole('dialog')).getByRole('button', { name: 'Remove' }),
    )
    await waitFor(() => {
      expect(screen.queryByRole('listitem', { name: 'Claude' })).not.toBeInTheDocument()
    })
  })
})

const router: AIProvider = {
  ...claude,
  id: 'router',
  kind: 'openrouter',
  name: 'OpenRouter',
  model: 'meta-llama/llama-3.3-70b-instruct:free',
  has_api_key: false,
}

test('sign in opens the vendor URL in a new tab', async () => {
  stubApi({
    'GET /api/settings/ai': () => ({
      body: { providers: [router], default_provider: 'router' } satisfies AIConfig,
    }),
    'POST /api/settings/ai/providers/router/sign-in': () => ({
      body: { url: 'https://openrouter.ai/auth?callback_url=x' },
    }),
  })
  const open = vi.fn()
  vi.stubGlobal('open', open)
  renderCard()
  const row = await screen.findByRole('listitem', { name: 'OpenRouter' })
  expect(within(row).getByText('no key')).toBeInTheDocument()
  await userEvent.click(within(row).getByRole('button', { name: 'Sign in' }))
  await waitFor(() => {
    expect(open).toHaveBeenCalledWith(
      'https://openrouter.ai/auth?callback_url=x',
      '_blank',
      'noopener',
    )
  })
})

test('sign out forgets the credential of a signed-in provider', async () => {
  let config: AIConfig = {
    providers: [{ ...router, has_api_key: true }],
    default_provider: 'router',
  }
  const api = stubApi({
    'GET /api/settings/ai': () => ({ body: config }),
    'DELETE /api/settings/ai/providers/router/credential': () => {
      config = { ...config, providers: [router] }
      return { body: config }
    },
  })
  renderCard()
  const row = await screen.findByRole('listitem', { name: 'OpenRouter' })
  expect(within(row).getByText('key set')).toBeInTheDocument()
  expect(within(row).queryByRole('button', { name: 'Sign in' })).not.toBeInTheDocument()
  await userEvent.click(within(row).getByRole('button', { name: 'OpenRouter actions' }))
  await userEvent.click(screen.getByRole('menuitem', { name: 'Sign out' }))
  await waitFor(() => {
    expect(
      api.calls.some((c) => c.key === 'DELETE /api/settings/ai/providers/router/credential'),
    ).toBe(true)
  })
  expect(await within(row).findByText('no key')).toBeInTheDocument()
})
