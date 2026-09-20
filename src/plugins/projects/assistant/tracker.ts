import { formatCost, formatTokens } from '@mvp/kanban-model'
import { phaseDurations, type AssistantState, type Step } from '@mvp/state'

export const STEP_LABELS: Record<Step, string> = {
  resolve: 'Prepare',
  context: 'Context',
  wait: 'Wait for model',
  stream: 'Streaming',
  validate: 'Validate',
  done: 'Done',
}

/** The steps shown as a tracker; `context` folds into Prepare, `done` completes Validate. */
export const TRACKER: Step[] = ['resolve', 'wait', 'stream', 'validate']

export type StepState = 'todo' | 'active' | 'done' | 'failed'

export interface Tracker {
  steps: { step: Step; label: string; state: StepState }[]
  /** One line: provider · phase or total time · tokens · cost. */
  summary: string
  durations: Partial<Record<Step, number>>
}

/** Pure view model of the activity panel, so the maths is testable without the DOM. */
export function trackerState(
  assistant: AssistantState,
  elapsedMs: number,
  providerLabel: string | null,
): Tracker {
  const running = assistant.status === 'running'
  const failed = assistant.status === 'error'
  const durations = phaseDurations(assistant.log, elapsedMs)
  const position = (step: Step | null) =>
    step === null
      ? -1
      : step === 'context'
        ? 0
        : step === 'done'
          ? TRACKER.length
          : TRACKER.indexOf(step)
  const cursor = assistant.status === 'done' ? TRACKER.length : position(assistant.step)
  const current = TRACKER[Math.min(Math.max(cursor, 0), TRACKER.length - 1)] ?? 'resolve'
  const steps = TRACKER.map((step) => {
    const index = TRACKER.indexOf(step)
    const state: StepState =
      index < cursor ? 'done' : index === cursor ? (failed ? 'failed' : 'active') : 'todo'
    return { step, label: STEP_LABELS[step], state }
  })
  const firstToken = durations.wait
  const summary = [
    providerLabel,
    running
      ? `${STEP_LABELS[current]}… ${seconds(elapsedMs)}`
      : failed
        ? 'failed'
        : seconds(elapsedMs) +
          (firstToken !== undefined ? ` (first token ${seconds(firstToken)})` : ''),
    assistant.usage && formatTokens(assistant.usage),
    assistant.usage && assistant.usage.cost_usd !== null
      ? formatCost(assistant.usage.cost_usd, assistant.usage.estimated)
      : null,
  ]
    .filter(Boolean)
    .join(' · ')
  return { steps, summary, durations }
}

export function seconds(ms: number): string {
  return ms < 1000 ? `${String(ms)} ms` : `${(ms / 1000).toFixed(1)} s`
}
