import { expect, test } from 'vitest'
import { createStore } from '@/app/store'
import { addApp, removeApp, selectApps } from './appsSlice'

test('plugin slice is injected into the root store and mutates', () => {
  const store = createStore()
  const initialCount = selectApps(store.getState()).length

  store.dispatch(addApp('new-app', 'eu'))
  const apps = selectApps(store.getState())
  expect(apps).toHaveLength(initialCount + 1)
  expect(apps.at(-1)).toMatchObject({ name: 'new-app', region: 'eu' })

  store.dispatch(removeApp(apps[0]?.id ?? ''))
  expect(selectApps(store.getState())).toHaveLength(initialCount)
})
