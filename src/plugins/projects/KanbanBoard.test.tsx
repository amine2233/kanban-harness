import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Provider } from 'react-redux'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { createStore } from '@/app/store'
import { stubApi, type Routes } from '@/test/fakeApi'
import { KanbanBoard } from './KanbanBoard'

const projectId = 'p1'
const base = `/api/projects/${projectId}/kanban/v1`
const board = { id: 'b1', name: 'Demo', description: null }
const columns = [
  { id: 'todo', board_id: 'b1', name: 'TODO', position: 0, wip_limit: null },
  { id: 'doing', board_id: 'b1', name: 'Doing', position: 1, wip_limit: 1 },
  { id: 'done', board_id: 'b1', name: 'Complete', position: 2, wip_limit: null },
]
const cardOf = (id: string, column_id: string, title: string, priority = 'medium') => ({
  id,
  column_id,
  board_id: 'b1',
  prefix: 'task',
  card_number: Number(id.replace(/\D/g, '')),
  title,
  description: null,
  priority,
  status: 'todo',
  position: 0,
})
const page = <T,>(items: T[]) => ({
  items,
  total: items.length,
  page: 1,
  page_size: 500,
  total_pages: 1,
})

function boardRoutes(cards: ReturnType<typeof cardOf>[], extra: Routes = {}) {
  return stubApi({
    [`GET ${base}/boards`]: () => ({ body: page([board]) }),
    [`GET ${base}/boards/b1/columns`]: () => ({ body: page(columns) }),
    [`GET ${base}/boards/b1/cards`]: () => ({ body: page(cards) }),
    ...extra,
  })
}

function renderBoard() {
  render(
    <Provider store={createStore()}>
      <KanbanBoard projectId={projectId} />
    </Provider>,
  )
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('KanbanBoard', () => {
  test('renders columns in order with their cards and WIP counters', async () => {
    boardRoutes([cardOf('c1', 'todo', 'Write tests'), cardOf('c2', 'doing', 'Ship', 'high')])
    renderBoard()

    const todo = await screen.findByRole('region', { name: 'TODO' })
    expect(within(todo).getByText('Write tests')).toBeInTheDocument()
    const doing = screen.getByRole('region', { name: 'Doing' })
    expect(within(doing).getByText('Ship')).toBeInTheDocument()
    expect(within(doing).getByText('1/1')).toBeInTheDocument()
    expect(within(doing).getByText('high')).toHaveClass('hk-badge--beta')
    expect(screen.getAllByRole('region').map((r) => r.getAttribute('aria-label'))).toEqual([
      'TODO',
      'Doing',
      'Complete',
    ])
  })

  test('creates a card in a column and refetches', async () => {
    const cards = [cardOf('c1', 'todo', 'Existing')]
    const api = boardRoutes(cards, {
      [`POST ${base}/columns/doing/cards`]: (body) => {
        const { title } = body as { title: string }
        cards.push(cardOf('c9', 'doing', title))
        return { status: 201, body: cards[cards.length - 1] }
      },
    })
    renderBoard()
    await screen.findByText('Existing')

    await userEvent.type(screen.getByLabelText('New card in Doing'), 'Brand new')
    await userEvent.click(
      within(screen.getByRole('region', { name: 'Doing' })).getByRole('button', { name: 'Add' }),
    )

    expect(
      await within(screen.getByRole('region', { name: 'Doing' })).findByText('Brand new'),
    ).toBeInTheDocument()
    const post = api.calls.find((c) => c.key === `POST ${base}/columns/doing/cards`)
    expect(post?.body).toEqual({ title: 'Brand new', priority: 'medium' })
    expect(screen.getByLabelText('New card in Doing')).toHaveValue('')
  })

  test('moves a card to the next column via PATCH', async () => {
    const cards = [cardOf('c1', 'todo', 'Task')]
    const api = boardRoutes(cards, {
      [`PATCH ${base}/boards/b1/cards/c1`]: (body) => {
        const { column_id } = body as { column_id: string }
        cards[0] = { ...cardOf('c1', column_id, 'Task') }
        return { body: cards[0] }
      },
    })
    renderBoard()
    await screen.findByText('Task')
    expect(screen.queryByRole('button', { name: 'Move Task to TODO' })).not.toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Move Task to Doing' }))

    await waitFor(() => {
      expect(
        within(screen.getByRole('region', { name: 'Doing' })).getByText('Task'),
      ).toBeInTheDocument()
    })
    const patch = api.calls.find((c) => c.key === `PATCH ${base}/boards/b1/cards/c1`)
    expect(patch?.body).toEqual({ column_id: 'doing' })
  })

  test('deletes a card', async () => {
    let cards = [cardOf('c1', 'todo', 'Doomed')]
    boardRoutes(cards, {
      [`DELETE ${base}/boards/b1/cards/c1`]: () => {
        cards = []
        return { status: 204 }
      },
      [`GET ${base}/boards/b1/cards`]: () => ({ body: page(cards) }),
    })
    renderBoard()
    await screen.findByText('Doomed')
    await userEvent.click(screen.getByRole('button', { name: 'Delete Doomed' }))
    await waitFor(() => {
      expect(screen.queryByText('Doomed')).not.toBeInTheDocument()
    })
  })

  test('shows an info banner when the project has no board', async () => {
    stubApi({ [`GET ${base}/boards`]: () => ({ body: page([]) }) })
    renderBoard()
    expect(await screen.findByText('This project has no board yet')).toBeInTheDocument()
  })

  test('shows the API error when boards cannot load', async () => {
    stubApi({})
    renderBoard()
    expect(await screen.findByText('Cannot load boards')).toBeInTheDocument()
  })
})
