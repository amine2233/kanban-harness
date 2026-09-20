import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { Provider } from 'react-redux'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { createStore } from '@mvp/state'
import { stubApi } from '@mvp/state/testing'
import { CARD_MIME, draggedCard, serialiseCardDrag } from './dragAndDrop'
import { KanbanBoard } from './KanbanBoard'

const projectId = 'p1'
const base = `/api/projects/${projectId}/kanban/v1`
const board = { id: 'b1', name: 'Demo', description: null, card_prefix: null, position: 0 }
const columns = [
  { id: 'todo', board_id: 'b1', name: 'TODO', position: 0, wip_limit: null, default_status: null },
  {
    id: 'done',
    board_id: 'b1',
    name: 'Complete',
    position: 1,
    wip_limit: null,
    default_status: null,
  },
]
const card = {
  id: 'c1',
  column_id: 'todo',
  board_id: 'b1',
  prefix: 'task',
  card_number: 1,
  title: 'Draggable',
  description: null,
  priority: 'medium',
  status: 'todo',
  position: 0,
  due_date: null,
  points: null,
  ai_cost: null,
  parent_id: null,
  children: { total: 0, done: 0 },
}
const page = <T,>(items: T[]) => ({
  items,
  total: items.length,
  page: 1,
  page_size: 500,
  total_pages: 1,
})

/** Minimal DataTransfer stand-in: jsdom has no constructor for it. */
function fakeDataTransfer() {
  const data = new Map<string, string>()
  return {
    setData: (type: string, value: string) => data.set(type, value),
    getData: (type: string) => data.get(type) ?? '',
    get types() {
      return [...data.keys()]
    },
    effectAllowed: 'uninitialized',
    dropEffect: 'none',
  }
}

afterEach(() => {
  vi.unstubAllGlobals()
})

test('drag payload round-trips and rejects foreign drags', () => {
  const dt = fakeDataTransfer()
  expect(draggedCard(dt as unknown as DataTransfer)).toBeNull()
  dt.setData(CARD_MIME, serialiseCardDrag('c1', 'todo'))
  expect(draggedCard(dt as unknown as DataTransfer)).toEqual({ cardId: 'c1', columnId: 'todo' })
})

describe('drag and drop between columns', () => {
  test('dropping a card on another column moves it; same column is a no-op', async () => {
    let cards = [card]
    const api = stubApi({
      [`GET ${base}/boards`]: () => ({ body: page([board]) }),
      [`GET ${base}/boards/b1/columns`]: () => ({ body: page(columns) }),
      [`GET ${base}/boards/b1/cards`]: () => ({ body: page(cards) }),
      [`PATCH ${base}/boards/b1/cards/c1`]: (body) => {
        cards = [{ ...card, column_id: (body as { column_id: string }).column_id }]
        return { body: cards[0] }
      },
    })
    render(
      <Provider store={createStore()}>
        <KanbanBoard projectId={projectId} />
      </Provider>,
    )
    const item = await screen.findByRole('listitem', { name: 'Draggable (medium)' })
    const todo = screen.getByRole('region', { name: 'TODO' })
    const done = screen.getByRole('region', { name: 'Complete' })

    const dataTransfer = fakeDataTransfer()
    fireEvent.dragStart(item, { dataTransfer })
    expect(dataTransfer.getData(CARD_MIME)).toBe('c1|todo')

    fireEvent.dragOver(todo, { dataTransfer })
    fireEvent.drop(todo, { dataTransfer })
    expect(api.calls.some((c) => c.key === `PATCH ${base}/boards/b1/cards/c1`)).toBe(false)

    fireEvent.dragOver(done, { dataTransfer })
    expect(done).toHaveClass('ds-column--drag-over')
    fireEvent.drop(done, { dataTransfer })
    expect(done).not.toHaveClass('ds-column--drag-over')

    await waitFor(() => {
      expect(within(done).getByText('Draggable')).toBeInTheDocument()
    })
    expect(api.calls.find((c) => c.key === `PATCH ${base}/boards/b1/cards/c1`)?.body).toEqual({
      column_id: 'done',
    })
  })

  test('columns ignore drags that are not cards', async () => {
    stubApi({
      [`GET ${base}/boards`]: () => ({ body: page([board]) }),
      [`GET ${base}/boards/b1/columns`]: () => ({ body: page(columns) }),
      [`GET ${base}/boards/b1/cards`]: () => ({ body: page([card]) }),
    })
    render(
      <Provider store={createStore()}>
        <KanbanBoard projectId={projectId} />
      </Provider>,
    )
    const done = await screen.findByRole('region', { name: 'Complete' })
    const dataTransfer = fakeDataTransfer()
    dataTransfer.setData('text/plain', 'just text')
    fireEvent.dragOver(done, { dataTransfer })
    expect(done).not.toHaveClass('ds-column--drag-over')
  })
})
