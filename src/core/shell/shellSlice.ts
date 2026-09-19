import { createSlice } from '@reduxjs/toolkit'

export interface ShellState {
  sidebarCollapsed: boolean
}

const initialState: ShellState = { sidebarCollapsed: false }

export const shellSlice = createSlice({
  name: 'shell',
  initialState,
  reducers: {
    toggleSidebar(state) {
      state.sidebarCollapsed = !state.sidebarCollapsed
    },
  },
  selectors: {
    selectSidebarCollapsed: (state) => state.sidebarCollapsed,
  },
})

export const { toggleSidebar } = shellSlice.actions
export const { selectSidebarCollapsed } = shellSlice.selectors
