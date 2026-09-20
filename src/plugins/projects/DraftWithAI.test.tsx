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
  const draft = {
    title: 'Add password reset',
    description: 'Users forget passwords',
    acceptance_criteria: ['Email sent'],
    priority: 'high',
    points: 5,
    subtasks: [
      { title: 'Login entry point', description: null, points: 2 },
      { title: 'Call the reset endpoint', description: 'd', points: null },
    ],
  }
  const usage = { input_tokens: 2, output_tokens: 400, cost_usd: 0.03, estimated: true }

  test('streams partials into the form, shows progress and cost, stamps the card on Create', async () => {
    const api = stubApi({
      'GET /api/settings/ai': () => ({ body: providers }),
      'POST /api/projects/p1/ai/tickets/draft': (body) => ({
        sse: [
          ['stage', { step: 'resolve', detail: null, elapsed_ms: 0 }],
          ['stage', { step: 'resolve', detail: 'Ollama (llama3.2)', elapsed_ms: 1 }],
          ['stage', { step: 'context', detail: '4 columns, 0 cards, ~40 tokens', elapsed_ms: 2 }],
          ['stage', { step: 'wait', detail: null, elapsed_ms: 3 }],
          ['stage', { step: 'stream', detail: null, elapsed_ms: 2003 }],
          ['text', { delta: '{"title":"Add pass' }],
          ['partial', { title: 'Add pass' }],
          ['text', { delta: 'word reset","priority":"high"' }],
          [
            'partial',
            {
              title: 'Add password reset',
              priority: 'high',
              subtasks: [{ title: 'Login entry point' }],
            },
          ],
          ['usage', usage],
          ['stage', { step: 'validate', detail: null, elapsed_ms: 6003 }],
          ['stage', { step: 'done', detail: null, elapsed_ms: 6004 }],
          [
            'result',
            {
              draft,
              provider: (body as { provider?: string }).provider ?? 'cc',
              model: 'llama3.2',
              usage,
            },
          ],
        ],
      }),
      'POST /api/projects/p1/kanban/v1/columns/todo/cards': (body) => ({
        status: 201,
        body: { ...(body as object), id: 'c1', column_id: 'todo', board_id: 'b1' },
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
    const activity = within(assist).getByRole('status', { name: 'AI activity' })
    expect(activity).toHaveTextContent(
      'Ollama · llama3.2 · 6.0 s (first token 2.0 s) · 2 in / 400 out · ≈ $0.0300',
    )
    const steps = within(within(activity).getByRole('list', { name: 'Steps' })).getAllByRole(
      'listitem',
    )
    expect(steps).toHaveLength(4)
    for (const step of steps) expect(step.className).toContain('--done')
    expect(within(activity).getByRole('list', { name: 'Draft fields' })).toHaveTextContent(
      '✓ title✓ description✓ criteria 1✓ priority✓ points✓ subtasks 2',
    )
    await userEvent.click(within(activity).getByText('Details'))
    expect(within(activity).getByRole('row', { name: /Wait for model/ })).toHaveTextContent('2.0 s')
    expect(within(activity).getByRole('row', { name: /Streaming/ })).toHaveTextContent('4.0 s')
    expect(within(activity).getByRole('row', { name: /Context/ })).toHaveTextContent(
      '4 columns, 0 cards',
    )
    await userEvent.click(within(activity).getByText('Raw output'))
    expect(activity).toHaveTextContent('{"title":"Add password reset","priority":"high"')

    const post = api.calls.find((c) => c.key === 'POST /api/projects/p1/ai/tickets/draft')
    expect(post?.body).toEqual({
      idea: 'password reset on mobile',
      board_id: 'b1',
      provider: 'local',
    })

    const subtasks = screen.getByRole('group', { name: /Sub-tasks \(2\/2\)/ })
    await userEvent.click(
      within(subtasks).getByLabelText('Create sub-task Call the reset endpoint'),
    )
    await userEvent.type(within(subtasks).getByLabelText('Sub-task 1 title'), ' on iOS')
    await userEvent.click(screen.getByRole('button', { name: 'Create 1 + 1 cards' }))
    await waitFor(() => {
      expect(
        api.calls.some((c) => c.key === 'POST /api/projects/p1/kanban/v1/columns/todo/cards'),
      ).toBe(true)
    })
    const created = api.calls.find(
      (c) => c.key === 'POST /api/projects/p1/kanban/v1/columns/todo/cards',
    )
    expect((created?.body as { subtasks: unknown }).subtasks).toEqual([
      { title: 'Login entry point on iOS', description: null, points: 2 },
    ])
    expect((created?.body as { ai_cost: unknown }).ai_cost).toEqual({
      provider: 'local',
      model: 'llama3.2',
      input_tokens: 2,
      output_tokens: 400,
      cost_usd: 0.03,
      estimated: true,
    })
  })

  test('shows the error code from the stream and from a plain error response', async () => {
    stubApi({
      'GET /api/settings/ai': () => ({ body: providers }),
      'POST /api/projects/p1/ai/tickets/draft': (body) =>
        (body as { idea: string }).idea === 'plain'
          ? { status: 502, body: { code: 'AI_PROVIDER', message: 'gateway said no' } }
          : {
              sse: [
                ['stage', { step: 'resolve', detail: null, elapsed_ms: 0 }],
                ['stage', { step: 'wait', detail: null, elapsed_ms: 5 }],
                ['error', { code: 'AI_PROVIDER', message: 'provider unavailable: offline' }],
              ],
            },
    })
    renderDialog()
    await userEvent.click(screen.getByRole('button', { name: '✨ Draft with AI' }))
    const idea = await screen.findByLabelText('Describe the ticket in a sentence or two')
    await userEvent.type(idea, 'x')
    await userEvent.click(screen.getByRole('button', { name: 'Draft' }))
    expect(await screen.findByText('provider unavailable: offline')).toBeInTheDocument()
    const activity = screen.getByRole('status', { name: 'AI activity' })
    expect(activity).toHaveTextContent('AI_PROVIDER')
    expect(within(activity).getAllByRole('listitem')[1]?.className).toContain('--failed')

    await userEvent.clear(idea)
    await userEvent.type(idea, 'plain')
    await userEvent.click(screen.getByRole('button', { name: 'Draft' }))
    expect(await screen.findByText('gateway said no')).toBeInTheDocument()
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
