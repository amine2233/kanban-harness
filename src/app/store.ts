import { configureStore } from '@reduxjs/toolkit'
import { rootReducer } from './reducer'

export const createStore = () => configureStore({ reducer: rootReducer })

export type AppStore = ReturnType<typeof createStore>
export type AppDispatch = AppStore['dispatch']
