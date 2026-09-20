import { combineSlices } from '@reduxjs/toolkit'
import { settingsSlice } from '@/core/settings/settingsSlice'
import { shellSlice } from '@/core/shell/shellSlice'
import { baseApi } from './api'

// Plugins add their state with `slice.injectInto(rootReducer)` and augment
// LazyLoadedSlices so RootState knows about it (see README, "Adding a web plugin").
// eslint-disable-next-line @typescript-eslint/no-empty-object-type
export interface LazyLoadedSlices {}

export const rootReducer = combineSlices(
  shellSlice,
  settingsSlice,
  baseApi,
).withLazyLoadedSlices<LazyLoadedSlices>()

export type RootState = ReturnType<typeof rootReducer>
