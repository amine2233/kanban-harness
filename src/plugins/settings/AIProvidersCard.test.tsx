import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Provider } from 'react-redux'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { createStore } from '@/app/store'
import { stubApi } from '@/test/fakeApi'
import { AIProvidersCard } from './AIProvidersCard'
import type { AIConfig, AIProvider } from './aiConfigApi'

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
  has_api_key: true,
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
