import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Provider } from 'react-redux'
import { createMemoryRouter, RouterProvider } from 'react-router'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { createStore } from '@/app/store'
import { stubApi } from '@/test/fakeApi'
import { draftDescription } from './assistantApi'
import { CardDialog } from './CardDialog'

afterEach(() => {
  vi.unstubAllGlobals()
})

const scope = { projectId: 'p1', boardId: 'b1' }
const columns = [
  { id: 'todo', board_id: 'b1', name: 'To do', position: 0, wip_limit: null, default_status: null },
]
const boards = [{ id: 'b1', name: 'Demo', description: null, card_prefix: null, position: 0 }]
const providers = {
  providers: [
    {
      id: 'cc',
      kind: 'claude_code',
      name: 'Claude Code',
      model: 'sonnet',
      base_url: null,
      max_tokens: null,
      has_api_key: false,
    },
    {
      id: 'local',
      kind: 'ollama',
      name: 'Ollama',
      model: 'llama3.2',
      base_url: null,
      max_tokens: null,
      has_api_key: false,
    },
  ],
  default_provider: 'cc',
}

function renderDialog() {
  const router = createMemoryRouter([
    {
      path: '/',
      element: (
        <CardDialog
          scope={scope}
          columns={columns}
          boards={boards}
          columnId="todo"
          onClose={vi.fn()}
        />
      ),
    },
  ])
  render(
    <Provider store={createStore()}>
      <RouterProvider router={router} />
    </Provider>,
  )
}

test('draftDescription renders criteria as a checklist', () => {
  expect(
    draftDescription({
      title: 't',
      description: 'Why',
      acceptance_criteria: ['a', 'b'],
      priority: 'medium',
      points: null,
    }),
  ).toBe('Why\n\n**Acceptance criteria**\n- [ ] a\n- [ ] b')
  expect(
    draftDescription({
      title: 't',
      description: null,
      acceptance_criteria: [],
      priority: 'low',
      points: null,
    }),
  ).toBe('')
})

describe('DraftWithAI', () => {
  test('fills the card form from the draft without creating anything', async () => {
    const api = stubApi({
      'GET /api/settings/ai': () => ({ body: providers }),
      'POST /api/projects/p1/ai/tickets/draft': (body) => ({
        body: {
          draft: {
            title: 'Add password reset',
            description: 'Users forget passwords',
            acceptance_criteria: ['Email sent'],
            priority: 'high',
            points: 5,
          },
          provider: (body as { provider?: string }).provider ?? 'cc',
          model: 'sonnet',
          usage: { input_tokens: 1, output_tokens: 2, cost_usd: 0.01 },
        },
      }),
    })
    renderDialog()
    await userEvent.click(screen.getByRole('button', { name: '✨ Draft with AI' }))
    const assist = await screen.findByRole('region', { name: 'Draft with AI' })
    expect(within(assist).getByRole('button', { name: 'Draft' })).toBeDisabled()
    await userEvent.type(
      within(assist).getByLabelText('Describe the ticket in a sentence or two'),
      'password reset on mobile',
    )
    await userEvent.selectOptions(within(assist).getByLabelText('Provider'), 'local')
    await userEvent.click(within(assist).getByRole('button', { name: 'Draft' }))

    await waitFor(() => {
      expect(screen.getByLabelText('Title')).toHaveValue('Add password reset')
    })
    expect(screen.getByLabelText('Description')).toHaveValue(
      'Users forget passwords\n\n**Acceptance criteria**\n- [ ] Email sent',
    )
    expect(screen.getByLabelText('Priority')).toHaveValue('high')
    expect(screen.getByText(/Drafted by local/)).toBeInTheDocument()
    const post = api.calls.find((c) => c.key === 'POST /api/projects/p1/ai/tickets/draft')
    expect(post?.body).toEqual({
      idea: 'password reset on mobile',
      board_id: 'b1',
      provider: 'local',
    })
    expect(api.calls.some((c) => c.key.startsWith('POST /api/projects/p1/kanban'))).toBe(false)
  })

  test('shows the provider error', async () => {
    stubApi({
      'GET /api/settings/ai': () => ({ body: providers }),
      'POST /api/projects/p1/ai/tickets/draft': () => ({
        status: 502,
        body: { code: 'AI_PROVIDER', message: 'provider unavailable: offline' },
      }),
    })
    renderDialog()
    await userEvent.click(screen.getByRole('button', { name: '✨ Draft with AI' }))
    await userEvent.type(
      await screen.findByLabelText('Describe the ticket in a sentence or two'),
      'x',
    )
    await userEvent.click(screen.getByRole('button', { name: 'Draft' }))
    expect(await screen.findByText('provider unavailable: offline')).toBeInTheDocument()
  })

  test('points to Settings when no provider is configured', async () => {
    stubApi({ 'GET /api/settings/ai': () => ({ body: { providers: [], default_provider: null } }) })
    renderDialog()
    await userEvent.click(screen.getByRole('button', { name: '✨ Draft with AI' }))
    expect(await screen.findByText(/No AI provider configured yet/)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Settings → AI providers' })).toHaveAttribute(
      'href',
      '/settings',
    )
  })
})
