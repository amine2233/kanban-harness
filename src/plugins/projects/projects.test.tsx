import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { ReactNode } from 'react'
import { Provider } from 'react-redux'
import { createMemoryRouter, RouterProvider } from 'react-router'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { createStore } from '@/app/store'
import { stubApi } from '@/test/fakeApi'
import { folderName } from './paths'
import { ProjectPage } from './ProjectPage'
import { ProjectsSidebar } from './ProjectsSidebar'

const demo = {
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Demo',
  path: '/tmp/demo',
  storage: 'json',
  created_at: '2026-01-01T00:00:00Z',
}

interface RenderOptions {
  route: string
  url?: string
  element: ReactNode
  extraRoutes?: { path: string; element: ReactNode }[]
}

function renderAt({ route, url = route, element, extraRoutes = [] }: RenderOptions) {
  const router = createMemoryRouter([{ path: route, element }, ...extraRoutes], {
    initialEntries: [url],
  })
  render(
    <Provider store={createStore()}>
      <RouterProvider router={router} />
    </Provider>,
  )
  return router
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('folderName', () => {
  test('takes the last path segment and ignores trailing slashes', () => {
    expect(folderName('/a/b/demo/')).toBe('demo')
    expect(folderName('C:\\work\\Thing')).toBe('Thing')
    expect(folderName('/')).toBe('project')
  })
})

describe('ProjectsSidebar', () => {
  test('shows an empty state when nothing is registered', async () => {
    stubApi({ 'GET /api/projects': () => ({ body: [] }) })
    renderAt({ route: '/', element: <ProjectsSidebar /> })
    expect(await screen.findByText('No projects yet')).toBeInTheDocument()
  })

  test('lists projects as links', async () => {
    stubApi({ 'GET /api/projects': () => ({ body: [demo] }) })
    renderAt({ route: '/', element: <ProjectsSidebar /> })
    const link = await screen.findByRole('link', { name: 'Demo' })
    expect(link).toHaveAttribute('href', `/projects/${demo.id}`)
  })

  test('adds a project through the inline form and navigates to it', async () => {
    let projects: unknown[] = []
    const api = stubApi({
      'GET /api/projects': () => ({ body: projects }),
      'POST /api/projects': () => {
        projects = [demo]
        return { status: 201, body: demo }
      },
    })
    const router = renderAt({
      route: '/',
      element: <ProjectsSidebar />,
      extraRoutes: [{ path: '/projects/:id', element: <p>project page</p> }],
    })
    await screen.findByText('No projects yet')

    await userEvent.click(screen.getByRole('button', { name: 'Add project' }))
    await userEvent.type(screen.getByLabelText('Folder path'), '/tmp/demo')
    await userEvent.selectOptions(screen.getByLabelText('Storage'), 'sqlite')
    await userEvent.click(screen.getByRole('button', { name: 'Add' }))

    await waitFor(() => {
      expect(router.state.location.pathname).toBe(`/projects/${demo.id}`)
    })
    const post = api.calls.find((c) => c.key === 'POST /api/projects')
    expect(post?.body).toEqual({ name: 'demo', path: '/tmp/demo', storage: 'sqlite' })
  })

  test('surfaces the API error message when adding fails', async () => {
    stubApi({
      'GET /api/projects': () => ({ body: [] }),
      'POST /api/projects': () => ({
        status: 409,
        body: { code: 'ALREADY_EXISTS', message: "a project named 'Demo' already exists" },
      }),
    })
    renderAt({ route: '/', element: <ProjectsSidebar /> })
    await userEvent.click(await screen.findByRole('button', { name: 'Add project' }))
    await userEvent.type(screen.getByLabelText('Folder path'), '/tmp/demo')
    await userEvent.click(screen.getByRole('button', { name: 'Add' }))
    expect(await screen.findByText("a project named 'Demo' already exists")).toBeInTheDocument()
  })
})

describe('ProjectPage', () => {
  test('renders project details and unregisters after confirmation', async () => {
    const api = stubApi({
      [`GET /api/projects/${demo.id}`]: () => ({ body: demo }),
      [`DELETE /api/projects/${demo.id}`]: () => ({ status: 204 }),
    })
    vi.stubGlobal('confirm', () => true)
    const router = renderAt({
      route: '/projects/:id',
      url: `/projects/${demo.id}`,
      element: <ProjectPage />,
      extraRoutes: [{ path: '/', element: <p>home</p> }],
    })

    expect(await screen.findByRole('heading', { level: 1 })).toHaveTextContent('Demo')
    expect(screen.getByText('/tmp/demo')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Unregister' }))
    await waitFor(() => {
      expect(router.state.location.pathname).toBe('/')
    })
    expect(api.calls.some((c) => c.key === `DELETE /api/projects/${demo.id}`)).toBe(true)
  })

  test('shows a not-found banner for an unknown id', async () => {
    stubApi({})
    renderAt({ route: '/projects/:id', url: '/projects/missing', element: <ProjectPage /> })
    expect(await screen.findByText('Project not found')).toBeInTheDocument()
  })
})
