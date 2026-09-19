import { configureStore } from '@reduxjs/toolkit'
import { baseApi } from './api'
import { rootReducer } from './reducer'

export const createStore = () =>
  configureStore({
    reducer: rootReducer,
    middleware: (getDefaultMiddleware) => getDefaultMiddleware().concat(baseApi.middleware),
  })

export type AppStore = ReturnType<typeof createStore>
export type AppDispatch = AppStore['dispatch']
