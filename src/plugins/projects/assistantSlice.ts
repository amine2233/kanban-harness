import { createAsyncThunk, createSlice, type PayloadAction, type WithSlice } from '@reduxjs/toolkit'
import { rootReducer, type RootState } from '@/app/reducer'
import { apiBaseUrl, selectServerUrl } from '@/core/settings/settingsSlice'
import type { DraftTicketResponse, PartialTicketDraft } from './assistantApi'
import { readEventStream } from './sse'

export interface Stage {
  name: string
  elapsed_ms: number
}

export interface Usage {
  input_tokens: number | null
  output_tokens: number | null
  cost_usd: number | null
}

export type AssistantFrame =
  | { event: 'stage'; data: Stage }
  | { event: 'partial'; data: PartialTicketDraft }
  | { event: 'usage'; data: Usage }
  | { event: 'result'; data: DraftTicketResponse }
  | { event: 'error'; data: { code: string; message: string } }

export interface AssistantState {
  status: 'idle' | 'running' | 'done' | 'error'
  startedAt: number | null
  stage: string | null
  elapsedMs: number
  log: Stage[]
  partial: PartialTicketDraft | null
  usage: Usage | null
  result: DraftTicketResponse | null
  error: string | null
}

const initialState: AssistantState = {
  status: 'idle',
  startedAt: null,
  stage: null,
  elapsedMs: 0,
  log: [],
  partial: null,
  usage: null,
  result: null,
  error: null,
}

export interface DraftArgs {
  projectId: string
  boardId: string
  idea: string
  provider?: string
}

/** One draft at a time; frames land in the store as they arrive. Abort with `.abort()`. */
export const streamDraft = createAsyncThunk<undefined, DraftArgs, { state: RootState }>(
  'assistant/streamDraft',
  async ({ projectId, boardId, idea, provider }, { dispatch, getState, signal }) => {
    const base = apiBaseUrl(selectServerUrl(getState()))
    const response = await fetch(`${base}/projects/${projectId}/ai/tickets/draft`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'text/event-stream' },
      body: JSON.stringify({ idea, board_id: boardId, ...(provider ? { provider } : {}) }),
      signal,
    })
    if (!response.ok || !response.body) {
      const body = (await response.json().catch(() => null)) as { message?: string } | null
      throw new Error(body?.message ?? `Request failed (${String(response.status)})`)
    }
    await readEventStream(response.body, (event, data) => {
      const frame = { event, data: JSON.parse(data) as never } as AssistantFrame
      if (frame.event === 'error') throw new Error(frame.data.message)
      dispatch(frameReceived(frame))
    })
    return undefined
  },
)

export const assistantSlice = createSlice({
  name: 'assistant',
  initialState,
  reducers: {
    frameReceived(state, action: PayloadAction<AssistantFrame>) {
      const frame = action.payload
      switch (frame.event) {
        case 'stage':
          state.stage = frame.data.name
          state.elapsedMs = frame.data.elapsed_ms
          state.log.push(frame.data)
          break
        case 'partial':
          state.partial = frame.data
          break
        case 'usage':
          state.usage = frame.data
          break
        case 'result':
          state.result = frame.data
          break
        case 'error':
          break
      }
    },
    resetDraft: () => initialState,
  },
  extraReducers: (builder) => {
    builder
      .addCase(streamDraft.pending, () => ({
        ...initialState,
        status: 'running',
        startedAt: Date.now(),
      }))
      .addCase(streamDraft.fulfilled, (state) => {
        state.status = state.result ? 'done' : 'error'
        if (!state.result) state.error = 'The stream ended without a draft'
      })
      .addCase(streamDraft.rejected, (state, action) => {
        state.status = action.meta.aborted ? 'idle' : 'error'
        state.error = action.meta.aborted ? null : (action.error.message ?? 'Request failed')
      })
  },
  selectors: {
    selectAssistant: (state) => state,
  },
})

declare module '@/app/reducer' {
  // eslint-disable-next-line @typescript-eslint/no-empty-object-type -- augmentation
  export interface LazyLoadedSlices extends WithSlice<typeof assistantSlice> {}
}

const injected = assistantSlice.injectInto(rootReducer)

export const { frameReceived, resetDraft } = assistantSlice.actions
export const { selectAssistant } = injected.selectors
