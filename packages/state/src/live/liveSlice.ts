import { createSlice, type PayloadAction } from '@reduxjs/toolkit'
import type { ChangeEvent } from './events'

export type LiveStatus = 'idle' | 'connecting' | 'open' | 'closed'

export interface LiveState {
  status: LiveStatus
  eventCount: number
  lastEvent: ChangeEvent | null
}

const initialState: LiveState = { status: 'idle', eventCount: 0, lastEvent: null }

/** Connection state of the server event socket; the middleware owns the socket itself. */
export const liveSlice = createSlice({
  name: 'live',
  initialState,
  reducers: {
    startLive: (state) => state,
    stopLive: (state) => state,
    liveConnecting(state) {
      state.status = 'connecting'
    },
    liveOpened(state) {
      state.status = 'open'
    },
    liveClosed(state) {
      state.status = 'closed'
    },
    liveEventReceived(state, action: PayloadAction<ChangeEvent>) {
      state.eventCount += 1
      state.lastEvent = action.payload
    },
  },
  selectors: {
    selectLiveStatus: (state) => state.status,
    selectLiveEventCount: (state) => state.eventCount,
  },
})

export const { startLive, stopLive, liveConnecting, liveOpened, liveClosed, liveEventReceived } =
  liveSlice.actions
export const { selectLiveStatus, selectLiveEventCount } = liveSlice.selectors
