import { combineSlices } from '@reduxjs/toolkit'
import { shellSlice } from '@/core/shell/shellSlice'
import { baseApi } from './api'

// Plugins add their state with `slice.injectInto(rootReducer)` and augment
// LazyLoadedSlices so RootState knows about it; see plugins/apps/appsSlice.ts.
// eslint-disable-next-line @typescript-eslint/no-empty-object-type
export interface LazyLoadedSlices {}

export const rootReducer = combineSlices(
  shellSlice,
  baseApi,
).withLazyLoadedSlices<LazyLoadedSlices>()

export type RootState = ReturnType<typeof rootReducer>
