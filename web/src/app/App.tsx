import { useEffect } from 'react'
import { Provider } from 'react-redux'
import { createBrowserRouter, Navigate, RouterProvider } from 'react-router'
import { AppShell } from '@/core/shell/AppShell'
import { registry } from './plugins'
import { createStore, startLive, stopLive } from '@mvp/state'

const store = createStore()

const router = createBrowserRouter([
  {
    element: <AppShell title="MVP Dashboard" registry={registry} />,
    children: [
      { index: true, element: <Navigate to={registry.nav[0]?.to ?? '/'} replace /> },
      ...registry.routes,
      { path: '*', element: <p>Not found</p> },
    ],
  },
])

export function App() {
  useEffect(() => {
    store.dispatch(startLive())
    return () => {
      store.dispatch(stopLive())
    }
  }, [])
  return (
    <Provider store={store}>
      <RouterProvider router={router} />
    </Provider>
  )
}
