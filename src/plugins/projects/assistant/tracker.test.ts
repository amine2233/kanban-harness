import { describe, expect, test } from 'vitest'
import type { AssistantState, Stage } from './assistantSlice'
import { seconds, trackerState } from './tracker'

const base: AssistantState = {
  status: 'idle',
  startedAt: null,
  step: null,
  elapsedMs: 0,
  log: [],
  text: '',
  partial: null,
  usage: null,
  result: null,
  error: null,
  sessionCostUSD: 0,
  sessionDrafts: 0,
}
const stage = (step: Stage['step'], elapsed_ms: number): Stage => ({
  step,
  detail: null,
  elapsed_ms,
})

describe('trackerState', () => {
  test('marks earlier steps done, the current one active, and folds context into Prepare', () => {
    const state = trackerState(
      {
        ...base,
        status: 'running',
        step: 'stream',
        log: [stage('resolve', 0), stage('context', 2), stage('wait', 3), stage('stream', 2003)],
      },
      3500,
      'cc · sonnet',
    )
    expect(state.steps.map((s) => s.state)).toEqual(['done', 'done', 'active', 'todo'])
    expect(state.summary).toBe('cc · sonnet · Streaming… 3.5 s')
    expect(state.durations).toEqual({ resolve: 2, context: 1, wait: 2000, stream: 1497 })
  })

  test('a finished draft shows total time, first token, tokens and cost', () => {
    const state = trackerState(
      {
        ...base,
        status: 'done',
        step: 'done',
        log: [
          stage('resolve', 0),
          stage('wait', 3),
          stage('stream', 2003),
          stage('validate', 6003),
          stage('done', 6004),
        ],
        usage: { input_tokens: 2, output_tokens: 400, cost_usd: 0.03, estimated: true },
      },
      6004,
      'Ollama · llama3.2',
    )
    expect(state.steps.every((s) => s.state === 'done')).toBe(true)
    expect(state.summary).toBe(
      'Ollama · llama3.2 · 6.0 s (first token 2.0 s) · 2 in / 400 out · ≈ $0.0300',
    )
  })

  test('a failure marks the step it failed on', () => {
    const state = trackerState(
      { ...base, status: 'error', step: 'wait', log: [stage('resolve', 0), stage('wait', 5)] },
      5,
      null,
    )
    expect(state.steps.map((s) => s.state)).toEqual(['done', 'failed', 'todo', 'todo'])
    expect(state.summary).toBe('failed')
    expect(
      trackerState({ ...base, status: 'error' }, 0, null).steps.every((s) => s.state === 'todo'),
    ).toBe(true)
  })

  test('seconds formats under and over a second', () => {
    expect(seconds(812)).toBe('812 ms')
    expect(seconds(6004)).toBe('6.0 s')
  })
})
