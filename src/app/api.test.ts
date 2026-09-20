import { afterEach, expect, test, vi } from 'vitest'
import { setServerUrl } from '@/core/settings/settingsSlice'
import { projectsApi } from '@/plugins/projects/api/projectsApi'
import { createStore } from './store'

afterEach(() => {
  localStorage.clear()
  vi.unstubAllGlobals()
})

test('requests follow the configured server url', async () => {
  const urls: string[] = []
  vi.stubGlobal(
    'fetch',
    vi.fn((input: RequestInfo | URL) => {
      urls.push(input instanceof Request ? input.url : String(input))
      return Promise.resolve(
        new Response('[]', { status: 200, headers: { 'content-type': 'application/json' } }),
      )
    }),
  )
  const store = createStore()
  await store.dispatch(projectsApi.endpoints.listProjects.initiate())
  expect(urls).toEqual([`${window.location.origin}/api/projects`])

  store.dispatch(setServerUrl('http://10.0.0.2:5175'))
  await store.dispatch(
    projectsApi.endpoints.listProjects.initiate(undefined, { forceRefetch: true }),
  )
  expect(urls[1]).toBe('http://10.0.0.2:5175/api/projects')
})
