import { combineSlices } from '@reduxjs/toolkit'
import { baseApi } from './api/baseApi'
import { assistantSlice } from './assistant/assistantSlice'
import { liveSlice } from './live/liveSlice'
import { settingsSlice } from './settings/settingsSlice'
import { shellSlice } from './shell/shellSlice'

/** One store: UI shell state, browser settings, the live socket, the AI assistant, and the API cache. */
export const rootReducer = combineSlices(
  shellSlice,
  settingsSlice,
  liveSlice,
  assistantSlice,
  baseApi,
)

export type RootState = ReturnType<typeof rootReducer>
