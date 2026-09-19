import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Provider } from 'react-redux'
import { createMemoryRouter, RouterProvider } from 'react-router'
import { expect, test } from 'vitest'
import { createStore } from '@/app/store'
import { AppShell } from './AppShell'

test('renders plugin nav and toggles sidebar', async () => {
  const router = createMemoryRouter([
    {
      element: <AppShell title="Test" nav={[{ label: 'Apps', to: '/apps', icon: 'grid' }]} />,
      children: [{ path: '/', element: <p>Home</p> }],
    },
  ])
  render(
    <Provider store={createStore()}>
      <RouterProvider router={router} />
    </Provider>,
  )

  expect(screen.getByRole('link', { name: 'Apps' })).toHaveAttribute('href', '/apps')
  await userEvent.click(screen.getByRole('button', { name: 'Toggle sidebar' }))
  expect(screen.getByRole('navigation', { name: 'Main' }).parentElement).toHaveClass(
    'ds-shell--collapsed',
  )
})
