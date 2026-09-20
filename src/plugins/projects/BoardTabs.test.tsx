import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Provider } from 'react-redux'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { createStore } from '@/app/store'
import { stubApi } from '@/test/fakeApi'
import { KanbanBoard } from './KanbanBoard'

const projectId = 'p1'
const base = `/api/projects/${projectId}/kanban/v1`
const board = (id: string, name: string, position: number) => ({
  id,
  name,
  description: null,
  card_prefix: null,
  position,
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

describe('BoardTabs', () => {
  test('lists boards as tabs, selects the first and switches on click', async () => {
    const boards = [board('b1', 'Alpha', 0), board('b2', 'Beta', 1)]
    const calls = stubApi({
      [`GET ${base}/boards`]: () => ({ body: page(boards) }),
      [`GET ${base}/boards/b1/columns`]: () => ({ body: page([]) }),
      [`GET ${base}/boards/b1/cards`]: () => ({ body: page([]) }),
      [`GET ${base}/boards/b2/columns`]: () => ({ body: page([]) }),
      [`GET ${base}/boards/b2/cards`]: () => ({ body: page([]) }),
    })
    renderBoard()
    const tabs = await screen.findByRole('tablist', { name: 'Boards' })
    expect(within(tabs).getByRole('tab', { name: 'Alpha' })).toHaveAttribute(
      'aria-selected',
      'true',
    )
    await userEvent.click(within(tabs).getByRole('tab', { name: 'Beta' }))
    expect(within(tabs).getByRole('tab', { name: 'Beta' })).toHaveAttribute('aria-selected', 'true')
    await waitFor(() => {
      expect(calls.calls.some((c) => c.key === `GET ${base}/boards/b2/columns`)).toBe(true)
    })
  })

  test('creates a board from the modal and selects it', async () => {
    let boards = [board('b1', 'Alpha', 0)]
    const api = stubApi({
      [`GET ${base}/boards`]: () => ({ body: page(boards) }),
      [`POST ${base}/boards`]: (body) => {
        const created = board('b9', (body as { name: string }).name, boards.length)
        boards = [...boards, created]
        return { status: 201, body: created }
      },
      [`GET ${base}/boards/b1/columns`]: () => ({ body: page([]) }),
      [`GET ${base}/boards/b1/cards`]: () => ({ body: page([]) }),
      [`GET ${base}/boards/b9/columns`]: () => ({ body: page([]) }),
      [`GET ${base}/boards/b9/cards`]: () => ({ body: page([]) }),
    })
    renderBoard()
    await userEvent.click(await screen.findByRole('button', { name: '+ New board' }))
    const dialog = screen.getByRole('dialog', { name: 'New board' })
    await userEvent.type(within(dialog).getByLabelText('Name'), 'Roadmap')
    await userEvent.type(within(dialog).getByLabelText('Card prefix (optional)'), 'RM')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create' }))

    await waitFor(() => {
      expect(screen.getByRole('tab', { name: 'Roadmap' })).toHaveAttribute('aria-selected', 'true')
    })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    const post = api.calls.find((c) => c.key === `POST ${base}/boards`)
    expect(post?.body).toEqual({ name: 'Roadmap', card_prefix: 'RM' })
  })

  test('renames, reorders, duplicates and deletes the selected board', async () => {
    let boards = [board('b1', 'Alpha', 0), board('b2', 'Beta', 1)]
    const api = stubApi({
      [`GET ${base}/boards`]: () => ({
        body: page([...boards].sort((a, b) => a.position - b.position)),
      }),
      [`PATCH ${base}/boards/b1`]: (body) => {
        const patch = body as { name?: string; position?: number }
        boards = boards.map((b) =>
          b.id === 'b1'
            ? { ...b, name: patch.name ?? b.name, position: patch.position ?? b.position }
            : b,
        )
        if (patch.position !== undefined)
          boards = boards.map((b) => (b.id === 'b2' ? { ...b, position: 0 } : b))
        return { body: boards.find((b) => b.id === 'b1') }
      },
      [`POST ${base}/boards/b1/clone`]: () => {
        const clone = board('b3', 'Alpha copy', 2)
        boards = [...boards, clone]
        return { status: 201, body: clone }
      },
      [`DELETE ${base}/boards/b3`]: () => {
        boards = boards.filter((b) => b.id !== 'b3')
        return { status: 204 }
      },
      ...Object.fromEntries(
        ['b1', 'b2', 'b3'].flatMap((id) => [
          [`GET ${base}/boards/${id}/columns`, () => ({ body: page([]) })],
          [`GET ${base}/boards/${id}/cards`, () => ({ body: page([]) })],
        ]),
      ),
    })
    renderBoard()
    await screen.findByRole('tab', { name: 'Alpha' })

    await userEvent.click(screen.getByRole('button', { name: 'Board actions' }))
    await userEvent.click(screen.getByRole('menuitem', { name: 'Rename' }))
    const dialog = screen.getByRole('dialog', { name: 'Rename board' })
    await userEvent.clear(within(dialog).getByLabelText('Name'))
    await userEvent.type(within(dialog).getByLabelText('Name'), 'Alpha 2')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save' }))
    expect(await screen.findByRole('tab', { name: 'Alpha 2' })).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Board actions' }))
    expect(screen.getByRole('menuitem', { name: 'Move left' })).toBeDisabled()
    await userEvent.click(screen.getByRole('menuitem', { name: 'Move right' }))
    await waitFor(() => {
      expect(screen.getAllByRole('tab').map((t) => t.textContent)).toEqual(['Beta', 'Alpha 2'])
    })
    expect(
      api.calls.find(
        (c) =>
          c.key === `PATCH ${base}/boards/b1` && (c.body as { position?: number }).position === 1,
      ),
    ).toBeTruthy()

    await userEvent.click(screen.getByRole('button', { name: 'Board actions' }))
    await userEvent.click(screen.getByRole('menuitem', { name: 'Duplicate' }))
    await waitFor(() => {
      expect(screen.getByRole('tab', { name: 'Alpha copy' })).toHaveAttribute(
        'aria-selected',
        'true',
      )
    })

    await userEvent.click(screen.getByRole('button', { name: 'Board actions' }))
    await userEvent.click(screen.getByRole('menuitem', { name: 'Delete board' }))
    await userEvent.click(
      within(screen.getByRole('dialog')).getByRole('button', { name: 'Delete' }),
    )
    await waitFor(() => {
      expect(screen.queryByRole('tab', { name: 'Alpha copy' })).not.toBeInTheDocument()
    })
    expect(api.calls.some((c) => c.key === `DELETE ${base}/boards/b3`)).toBe(true)
  })

  test('shows the API error inside the create modal', async () => {
    stubApi({
      [`GET ${base}/boards`]: () => ({ body: page([]) }),
      [`POST ${base}/boards`]: () => ({
        status: 400,
        body: { code: 'VALIDATION_FAILED', message: 'board name must not be empty' },
      }),
    })
    renderBoard()
    await userEvent.click(await screen.findByRole('button', { name: '+ New board' }))
    await userEvent.type(screen.getByLabelText('Name'), 'x')
    await userEvent.click(screen.getByRole('button', { name: 'Create' }))
    expect(await screen.findByText('board name must not be empty')).toBeInTheDocument()
  })
})
