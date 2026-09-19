import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Provider } from 'react-redux'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { createStore } from '@/app/store'
import { stubApi, type Routes } from '@/test/fakeApi'
import { KanbanBoard } from './KanbanBoard'

const projectId = 'p1'
const base = `/api/projects/${projectId}/kanban/v1`
const board = { id: 'b1', name: 'Demo', description: null, card_prefix: null, position: 0 }
const columns = [
  { id: 'todo', board_id: 'b1', name: 'TODO', position: 0, wip_limit: null, default_status: null },
  { id: 'doing', board_id: 'b1', name: 'Doing', position: 1, wip_limit: 1, default_status: null },
  {
    id: 'done',
    board_id: 'b1',
    name: 'Complete',
    position: 2,
    wip_limit: null,
    default_status: null,
  },
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
  due_date: null as string | null,
  points: null as number | null,
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

  test('creates a card from the modal and refetches', async () => {
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

    await userEvent.click(screen.getByRole('button', { name: 'Add card to Doing' }))
    const dialog = screen.getByRole('dialog', { name: 'New card' })
    expect(within(dialog).getByLabelText('Column')).toHaveValue('doing')
    await userEvent.type(within(dialog).getByLabelText('Title'), 'Brand new')
    await userEvent.type(within(dialog).getByLabelText('Description'), 'details')
    await userEvent.selectOptions(within(dialog).getByLabelText('Priority'), 'high')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create' }))

    expect(
      await within(screen.getByRole('region', { name: 'Doing' })).findByText('Brand new'),
    ).toBeInTheDocument()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    const post = api.calls.find((c) => c.key === `POST ${base}/columns/doing/cards`)
    expect(post?.body).toEqual({ title: 'Brand new', priority: 'high', description: 'details' })
  })

  test('edits a card in the modal: fields, column and due date', async () => {
    const cards = [cardOf('c1', 'todo', 'Editable')]
    const api = boardRoutes(cards, {
      [`PATCH ${base}/boards/b1/cards/c1`]: (body) => {
        const patch = body as { title: string; column_id?: string }
        cards[0] = { ...cardOf('c1', patch.column_id ?? 'todo', patch.title), points: 3 }
        return { body: cards[0] }
      },
    })
    renderBoard()
    await userEvent.click(await screen.findByRole('button', { name: 'Open Editable' }))
    const dialog = screen.getByRole('dialog', { name: 'task-1' })
    await userEvent.clear(within(dialog).getByLabelText('Title'))
    await userEvent.type(within(dialog).getByLabelText('Title'), 'Edited')
    await userEvent.selectOptions(within(dialog).getByLabelText('Status'), 'blocked')
    await userEvent.selectOptions(within(dialog).getByLabelText('Column'), 'done')
    await userEvent.type(within(dialog).getByLabelText('Due date'), '2026-12-24')
    await userEvent.type(within(dialog).getByLabelText('Points'), '3')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save' }))

    await waitFor(() => {
      expect(
        within(screen.getByRole('region', { name: 'Complete' })).getByText('Edited'),
      ).toBeInTheDocument()
    })
    const patch = api.calls.find((c) => c.key === `PATCH ${base}/boards/b1/cards/c1`)
    expect(patch?.body).toEqual({
      title: 'Edited',
      description: null,
      priority: 'medium',
      status: 'blocked',
      due_date: '2026-12-24T00:00:00.000Z',
      points: 3,
      column_id: 'done',
    })
    expect(screen.getByText('task-1 · 3 pt')).toBeInTheDocument()
  })

  test('moves a card to another board from the modal', async () => {
    const api = boardRoutes([cardOf('c1', 'todo', 'Traveller')], {
      [`GET ${base}/boards`]: () => ({
        body: page([board, { ...board, id: 'b2', name: 'Other', position: 1 }]),
      }),
      [`PATCH ${base}/boards/b1/cards/c1`]: () => ({
        body: { ...cardOf('c1', 'x', 'Traveller'), board_id: 'b2' },
      }),
    })
    renderBoard()
    await userEvent.click(await screen.findByRole('button', { name: 'Open Traveller' }))
    const dialog = screen.getByRole('dialog', { name: 'task-1' })
    await userEvent.selectOptions(within(dialog).getByLabelText('Board'), 'b2')
    expect(within(dialog).queryByLabelText('Column')).not.toBeInTheDocument()
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save' }))
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    })
    const patch = api.calls.find((c) => c.key === `PATCH ${base}/boards/b1/cards/c1`)
    expect((patch?.body as { board_id?: string }).board_id).toBe('b2')
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

  test('deletes a card after confirmation from the modal', async () => {
    let cards = [cardOf('c1', 'todo', 'Doomed')]
    boardRoutes(cards, {
      [`DELETE ${base}/boards/b1/cards/c1`]: () => {
        cards = []
        return { status: 204 }
      },
      [`GET ${base}/boards/b1/cards`]: () => ({ body: page(cards) }),
    })
    renderBoard()
    await userEvent.click(await screen.findByRole('button', { name: 'Open Doomed' }))
    await userEvent.click(
      within(screen.getByRole('dialog')).getByRole('button', { name: 'Delete' }),
    )
    await userEvent.click(
      within(screen.getByRole('dialog', { name: 'Delete "Doomed"?' })).getByRole('button', {
        name: 'Delete',
      }),
    )
    await waitFor(() => {
      expect(screen.queryByText('Doomed')).not.toBeInTheDocument()
    })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
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
