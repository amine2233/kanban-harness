import { configureStore } from '@reduxjs/toolkit'
import { liveMiddleware } from './live/liveMiddleware'
import { saveSettings, settingsSlice } from './settings/settingsSlice'
import { baseApi } from './api/baseApi'
import { rootReducer } from './reducer'

export const createStore = () => {
  const store = configureStore({
    reducer: rootReducer,
    middleware: (getDefaultMiddleware) =>
      getDefaultMiddleware().concat(baseApi.middleware, liveMiddleware),
  })
  let lastSettings = settingsSlice.selectSlice(store.getState())
  store.subscribe(() => {
    const settings = settingsSlice.selectSlice(store.getState())
    if (settings !== lastSettings) {
      lastSettings = settings
      saveSettings(settings)
    }
  })
  return store
}

export type AppStore = ReturnType<typeof createStore>
export type AppDispatch = AppStore['dispatch']
