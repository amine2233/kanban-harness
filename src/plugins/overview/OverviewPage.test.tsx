import { render, screen } from '@testing-library/react'
import { Provider } from 'react-redux'
import { createMemoryRouter, RouterProvider } from 'react-router'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { createStore } from '@/app/store'
import { stubApi } from '@/test/fakeApi'
import { OverviewPage } from './OverviewPage'

const page = <T,>(items: T[]) => ({
  items,
  total: items.length,
  page: 1,
  page_size: 500,
  total_pages: 1,
})

function renderPage() {
  const router = createMemoryRouter([{ path: '/', element: <OverviewPage /> }])
  render(
    <Provider store={createStore()}>
      <RouterProvider router={router} />
    </Provider>,
  )
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('OverviewPage', () => {
  test('shows an empty state with the add-project form', async () => {
    stubApi({
      'GET /api/projects': () => ({ body: [] }),
      'GET /api/settings': () => ({ body: { default_storage: 'json', cors_origins: [] } }),
    })
    renderPage()
    expect(await screen.findByText('No projects yet')).toBeInTheDocument()
    expect(screen.getByLabelText('Folder path')).toBeInTheDocument()
  })

  test('lists projects as tiles with storage and board names', async () => {
    stubApi({
      'GET /api/projects': () => ({
        body: [
          {
            id: 'p1',
            name: 'Mobile app',
            path: '/work/mobile',
            storage: 'sqlite',
            created_at: '2026-01-01T00:00:00Z',
          },
        ],
      }),
      'GET /api/projects/p1/kanban/v1/boards': () => ({
        body: page([
          { id: 'b1', name: 'Sprint', description: null, card_prefix: null, position: 0 },
          { id: 'b2', name: 'Roadmap', description: null, card_prefix: null, position: 1 },
        ]),
      }),
    })
    renderPage()
    const tile = await screen.findByRole('link', { name: /Mobile app/ })
    expect(tile).toHaveAttribute('href', '/projects/p1')
    expect(await screen.findByText('2 boards')).toBeInTheDocument()
    expect(screen.getByText('Sprint · Roadmap')).toBeInTheDocument()
    expect(screen.getByText('SQLITE')).toBeInTheDocument()
    expect(screen.getByText('1 project')).toBeInTheDocument()
  })
})
