import { createSlice, type PayloadAction, type WithSlice } from '@reduxjs/toolkit'
import { rootReducer } from '@/app/reducer'

export interface AppEntry {
  id: string
  name: string
  region: 'eu' | 'us'
}

export interface AppsState {
  items: AppEntry[]
}

const initialState: AppsState = {
  items: [
    { id: '1', name: 'billing-api', region: 'eu' },
    { id: '2', name: 'web-frontend', region: 'us' },
  ],
}

const slice = createSlice({
  name: 'apps',
  initialState,
  reducers: {
    addApp: {
      reducer(state, action: PayloadAction<AppEntry>) {
        state.items.push(action.payload)
      },
      prepare(name: string, region: AppEntry['region']) {
        return { payload: { id: crypto.randomUUID(), name, region } }
      },
    },
    removeApp(state, action: PayloadAction<string>) {
      state.items = state.items.filter((app) => app.id !== action.payload)
    },
  },
  selectors: {
    selectApps: (state) => state.items,
  },
})

declare module '@/app/reducer' {
  // eslint-disable-next-line @typescript-eslint/no-empty-object-type
  export interface LazyLoadedSlices extends WithSlice<typeof slice> {}
}

export const appsSlice = slice.injectInto(rootReducer)
export const { addApp, removeApp } = appsSlice.actions
export const { selectApps } = appsSlice.selectors
