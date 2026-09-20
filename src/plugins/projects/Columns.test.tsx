import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Provider } from 'react-redux'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { createStore } from '@/app/store'
import { stubApi } from '@/test/fakeApi'
import { KanbanBoard } from './KanbanBoard'
import type { CardStatus } from './kanbanApi'

const projectId = 'p1'
const base = `/api/projects/${projectId}/kanban/v1`
const board = { id: 'b1', name: 'Demo', description: null, card_prefix: null, position: 0 }
const col = (id: string, name: string, position: number, wip_limit: number | null = null) => ({
  id,
  board_id: 'b1',
  name,
  position,
  wip_limit,
  default_status: null as CardStatus | null,
})
const page = <T,>(items: T[]) => ({
  items,
  total: items.length,
  page: 1,
  page_size: 500,
  total_pages: 1,
})

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

describe('column management', () => {
  test('adds a column from the modal', async () => {
    let columns = [col('todo', 'TODO', 0)]
    const api = stubApi({
      [`GET ${base}/boards`]: () => ({ body: page([board]) }),
      [`GET ${base}/boards/b1/columns`]: () => ({ body: page(columns) }),
      [`GET ${base}/boards/b1/cards`]: () => ({ body: page([]) }),
      [`POST ${base}/boards/b1/columns`]: (body) => {
        const { name, wip_limit, default_status } = body as {
          name: string
          wip_limit: number | null
          default_status: CardStatus | null
        }
        columns = [...columns, { ...col('new', name, 1, wip_limit), default_status }]
        return { status: 201, body: columns[1] }
      },
    })
    renderBoard()
    await userEvent.click(await screen.findByRole('button', { name: '+ Add column' }))
    const dialog = screen.getByRole('dialog', { name: 'New column' })
    await userEvent.type(within(dialog).getByLabelText('Name'), 'Review')
    await userEvent.type(within(dialog).getByLabelText('WIP limit'), '2')
    await userEvent.selectOptions(within(dialog).getByLabelText('Default status'), 'blocked')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create' }))

    expect(await screen.findByRole('region', { name: 'Review' })).toBeInTheDocument()
    expect(
      within(screen.getByRole('region', { name: 'Review' })).getByText('0/2'),
    ).toBeInTheDocument()
    const post = api.calls.find((c) => c.key === `POST ${base}/boards/b1/columns`)
    expect(post?.body).toEqual({ name: 'Review', wip_limit: 2, default_status: 'blocked' })
  })

  test('edits, reorders and deletes columns', async () => {
    let columns = [col('todo', 'TODO', 0), col('doing', 'Doing', 1, 1)]
    const api = stubApi({
      [`GET ${base}/boards`]: () => ({ body: page([board]) }),
      [`GET ${base}/boards/b1/columns`]: () => ({
        body: page([...columns].sort((a, b) => a.position - b.position)),
      }),
      [`GET ${base}/boards/b1/cards`]: () => ({ body: page([]) }),
      [`PATCH ${base}/boards/b1/columns/doing`]: (body) => {
        const patch = body as { name?: string; position?: number; wip_limit?: number | null }
        columns = columns.map((c) =>
          c.id === 'doing'
            ? {
                ...c,
                name: patch.name ?? c.name,
                position: patch.position ?? c.position,
                wip_limit: patch.wip_limit === undefined ? c.wip_limit : patch.wip_limit,
              }
            : patch.position === 0
              ? { ...c, position: 1 }
              : c,
        )
        return { body: columns.find((c) => c.id === 'doing') }
      },
      [`DELETE ${base}/boards/b1/columns/todo`]: () => {
        columns = columns.filter((c) => c.id !== 'todo')
        return { status: 204 }
      },
    })
    renderBoard()
    await screen.findByRole('region', { name: 'Doing' })

    await userEvent.click(screen.getByRole('button', { name: 'Column Doing actions' }))
    await userEvent.click(screen.getByRole('menuitem', { name: 'Edit column' }))
    const dialog = screen.getByRole('dialog', { name: 'Edit column' })
    expect(within(dialog).getByLabelText('WIP limit')).toHaveValue(1)
    await userEvent.clear(within(dialog).getByLabelText('Name'))
    await userEvent.type(within(dialog).getByLabelText('Name'), 'In progress')
    await userEvent.clear(within(dialog).getByLabelText('WIP limit'))
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save' }))
    expect(await screen.findByRole('region', { name: 'In progress' })).toBeInTheDocument()
    expect(api.calls.find((c) => c.key === `PATCH ${base}/boards/b1/columns/doing`)?.body).toEqual({
      name: 'In progress',
      wip_limit: null,
      default_status: null,
    })

    await userEvent.click(screen.getByRole('button', { name: 'Column In progress actions' }))
    expect(screen.getByRole('menuitem', { name: 'Move right' })).toBeDisabled()
    await userEvent.click(screen.getByRole('menuitem', { name: 'Move left' }))
    await waitFor(() => {
      expect(screen.getAllByRole('region').map((r) => r.getAttribute('aria-label'))).toEqual([
        'In progress',
        'TODO',
      ])
    })

    await userEvent.click(screen.getByRole('button', { name: 'Column TODO actions' }))
    await userEvent.click(screen.getByRole('menuitem', { name: 'Delete column' }))
    await userEvent.click(
      within(screen.getByRole('dialog')).getByRole('button', { name: 'Delete' }),
    )
    await waitFor(() => {
      expect(screen.queryByRole('region', { name: 'TODO' })).not.toBeInTheDocument()
    })
    await userEvent.click(screen.getByRole('button', { name: 'Column In progress actions' }))
    expect(screen.getByRole('menuitem', { name: 'Delete column' })).toBeDisabled()
  })
})
