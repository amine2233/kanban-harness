import { createAsyncThunk, createSlice, type PayloadAction } from '@reduxjs/toolkit'
import type { RootState } from '../reducer'
import { apiBaseUrl, selectServerUrl } from '../settings/settingsSlice'
import type { DraftTicketResponse, PartialTicketDraft, Usage } from '@mvp/kanban-model'
import { readEventStream } from './sse'

export type Step = 'resolve' | 'context' | 'wait' | 'stream' | 'validate' | 'done'
export const STEPS: Step[] = ['resolve', 'context', 'wait', 'stream', 'validate', 'done']

export interface Stage {
  step: Step
  detail: string | null
  elapsed_ms: number
}

export interface AssistantError {
  code: string
  message: string
}

export type AssistantFrame =
  | { event: 'stage'; data: Stage }
  | { event: 'text'; data: { delta: string } }
  | { event: 'partial'; data: PartialTicketDraft }
  | { event: 'usage'; data: Usage }
  | { event: 'result'; data: DraftTicketResponse }
  | { event: 'error'; data: AssistantError }

export interface AssistantState {
  status: 'idle' | 'running' | 'done' | 'error'
  startedAt: number | null
  step: Step | null
  elapsedMs: number
  log: Stage[]
  text: string
  partial: PartialTicketDraft | null
  usage: Usage | null
  result: DraftTicketResponse | null
  error: AssistantError | null
  /** Sum of every priced draft since the page loaded. */
  sessionCostUSD: number
  sessionDrafts: number
}

const idle = {
  status: 'idle' as const,
  startedAt: null,
  step: null,
  elapsedMs: 0,
  log: [],
  text: '',
  partial: null,
  usage: null,
  result: null,
  error: null,
}

const initialState: AssistantState = { ...idle, sessionCostUSD: 0, sessionDrafts: 0 }

export interface DraftArgs {
  projectId: string
  boardId: string
  idea: string
  provider?: string
}

class DraftFailure extends Error {
  readonly failure: AssistantError
  constructor(failure: AssistantError) {
    super(failure.message)
    this.failure = failure
  }
}

/** One draft at a time; frames land in the store as they arrive. Abort with `.abort()`. */
export const streamDraft = createAsyncThunk<
  undefined,
  DraftArgs,
  { state: RootState; rejectValue: AssistantError }
>(
  'assistant/streamDraft',
  async (
    { projectId, boardId, idea, provider },
    { dispatch, getState, signal, rejectWithValue },
  ) => {
    const base = apiBaseUrl(selectServerUrl(getState()))
    try {
      const response = await fetch(`${base}/projects/${projectId}/ai/tickets/draft`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', accept: 'text/event-stream' },
        body: JSON.stringify({ idea, board_id: boardId, ...(provider ? { provider } : {}) }),
        signal,
      })
      if (!response.ok || !response.body) {
        const body = (await response.json().catch(() => null)) as Partial<AssistantError> | null
        throw new DraftFailure({
          code: body?.code ?? `HTTP_${String(response.status)}`,
          message: body?.message ?? `Request failed (${String(response.status)})`,
        })
      }
      await readEventStream(response.body, (event, data) => {
        const frame = { event, data: JSON.parse(data) as never } as AssistantFrame
        if (frame.event === 'error') throw new DraftFailure(frame.data)
        dispatch(frameReceived(frame))
      })
      return undefined
    } catch (error) {
      if (signal.aborted) throw error
      if (error instanceof DraftFailure) return rejectWithValue(error.failure)
      return rejectWithValue({
        code: 'NETWORK',
        message: error instanceof Error ? error.message : 'Request failed',
      })
    }
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
          state.step = frame.data.step
          state.elapsedMs = frame.data.elapsed_ms
          state.log.push(frame.data)
          break
        case 'text':
          state.text += frame.data.delta
          break
        case 'partial':
          state.partial = frame.data
          break
        case 'usage':
          state.usage = frame.data
          break
        case 'result':
          state.result = frame.data
          state.usage = frame.data.usage
          break
        case 'error':
          break
      }
    },
    resetDraft: (state) => ({ ...state, ...idle }),
  },
  extraReducers: (builder) => {
    builder
      .addCase(streamDraft.pending, (state) => ({
        ...state,
        ...idle,
        status: 'running',
        startedAt: Date.now(),
      }))
      .addCase(streamDraft.fulfilled, (state) => {
        if (state.result) {
          state.status = 'done'
          state.sessionDrafts += 1
          state.sessionCostUSD += state.result.usage.cost_usd ?? 0
        } else {
          state.status = 'error'
          state.error = { code: 'AI_PROVIDER', message: 'The stream ended without a draft' }
        }
      })
      .addCase(streamDraft.rejected, (state, action) => {
        if (action.meta.aborted) {
          state.status = 'idle'
          return
        }
        state.status = 'error'
        state.error = action.payload ?? {
          code: 'NETWORK',
          message: action.error.message ?? 'Request failed',
        }
      })
  },
  selectors: {
    selectAssistant: (state) => state,
  },
})

export const { frameReceived, resetDraft } = assistantSlice.actions
export const { selectAssistant } = assistantSlice.selectors

/** Wall time spent in each step, from consecutive stage timestamps. */
export function phaseDurations(log: Stage[], nowMs: number): Partial<Record<Step, number>> {
  const starts = new Map<Step, number>()
  for (const entry of log) if (!starts.has(entry.step)) starts.set(entry.step, entry.elapsed_ms)
  const ordered = [...starts.entries()]
  const durations: Partial<Record<Step, number>> = {}
  ordered.forEach(([step, start], i) => {
    const next = ordered[i + 1]
    durations[step] = Math.max(0, (next ? next[1] : nowMs) - start)
  })
  return durations
}
