import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Provider } from 'react-redux'
import { createMemoryRouter, RouterProvider } from 'react-router'
import { expect, test } from 'vitest'
import { createStore } from '@/app/store'
import { buildRegistry } from '@/core/plugin/registry'
import { AppShell } from './AppShell'

const registry = buildRegistry([
  {
    id: 'apps',
    name: 'Apps',
    nav: [{ label: 'Apps', to: '/apps', icon: 'grid' }],
    routes: [],
    sidebar: () => <p>Dynamic section</p>,
  },
])

test('renders plugin nav, sidebar sections and toggles sidebar', async () => {
  const router = createMemoryRouter([
    {
      element: <AppShell title="Test" registry={registry} />,
      children: [{ path: '/', element: <p>Home</p> }],
    },
  ])
  render(
    <Provider store={createStore()}>
      <RouterProvider router={router} />
    </Provider>,
  )

  expect(screen.getByRole('link', { name: 'Apps' })).toHaveAttribute('href', '/apps')
  expect(screen.getByText('Dynamic section')).toBeInTheDocument()
  await userEvent.click(screen.getByRole('button', { name: 'Toggle sidebar' }))
  expect(screen.getByRole('navigation', { name: 'Main' }).parentElement).toHaveClass(
    'ds-shell--collapsed',
  )
})
