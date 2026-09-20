import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router'
import { useAppDispatch, useAppSelector } from '@/app/hooks'
import { Button, cx, Select, Spinner, Textarea } from '@mvp/design-system'
import { useGetAIConfigQuery } from '@/plugins/settings/aiConfigApi'
import { costOf, draftPatch, formatCost, formatTokens, type DraftPatch } from '@mvp/kanban-model'
import { logText } from './assistantLog'
import {
  phaseDurations,
  resetDraft,
  selectAssistant,
  STEPS,
  streamDraft,
  type AssistantState,
  type Step,
} from './assistantSlice'

interface Props {
  scope: { projectId: string; boardId: string }
  /** Called with each partial and the final draft; the user still reviews and creates. */
  onDraft: (patch: DraftPatch) => void
}

/** Collapsible "✨ Draft with AI" block for the card dialog, streaming as the model types. */
export function DraftWithAI({ scope, onDraft }: Props) {
  const { data: ai } = useGetAIConfigQuery()
  const dispatch = useAppDispatch()
  const assistant = useAppSelector(selectAssistant)
  const [open, setOpen] = useState(false)
  const [idea, setIdea] = useState('')
  const [provider, setProvider] = useState('')
  const abort = useRef<() => void>(() => undefined)
  const providers = ai?.providers ?? []
  const noProvider = ai !== undefined && providers.length === 0
  const running = assistant.status === 'running'
  const chosen = providers.find((p) => p.id === (provider || ai?.default_provider))
  const [now, setNow] = useState(0)

  const draftSink = useRef(onDraft)
  useEffect(() => {
    draftSink.current = onDraft
  })
  useEffect(() => {
    if (assistant.partial) draftSink.current(draftPatch(assistant.partial))
  }, [assistant.partial])
  useEffect(() => {
    if (assistant.result) {
      draftSink.current({ ...draftPatch(assistant.result.draft), aiCost: costOf(assistant.result) })
    }
  }, [assistant.result])
  useEffect(
    () => () => {
      abort.current()
      dispatch(resetDraft())
    },
    [dispatch],
  )
  useEffect(() => {
    if (!running) return undefined
    const timer = setInterval(() => {
      setNow(Date.now())
    }, 250)
    return () => {
      clearInterval(timer)
    }
  }, [running])
  const elapsedMs =
    running && assistant.startedAt !== null
      ? Math.max(assistant.elapsedMs, now - assistant.startedAt)
      : assistant.elapsedMs

  const run = () => {
    const trimmed = idea.trim()
    if (!trimmed) return
    const promise = dispatch(
      streamDraft({ ...scope, idea: trimmed, ...(provider ? { provider } : {}) }),
    )
    abort.current = () => {
      promise.abort()
    }
  }

  if (!open) {
    return (
      <Button
        type="button"
        variant="tertiary"
        size="sm"
        className="mb2"
        onClick={() => {
          setOpen(true)
        }}
      >
        ✨ Draft with AI
      </Button>
    )
  }

  return (
    <section className="ds-assist mb3" aria-label="Draft with AI">
      {noProvider ? (
        <p className="f6 gray ma0">
          No AI provider configured yet — add one in{' '}
          <Link to="/settings">Settings → AI providers</Link>.
        </p>
      ) : (
        <>
          <Textarea
            name="ai-idea"
            label="Describe the ticket in a sentence or two"
            placeholder="Users can't reset their password from the mobile app"
            value={idea}
            rows={2}
            disabled={running}
            onChange={(e) => {
              setIdea(e.target.value)
            }}
            className="mb2"
          />
          <div className="flex items-end" style={{ gap: 8 }}>
            {providers.length > 1 && (
              <Select
                name="ai-provider"
                label="Provider"
                value={provider}
                className="flex-auto"
                disabled={running}
                onChange={(e) => {
                  setProvider(e.target.value)
                }}
              >
                <option value="">
                  Default ({providers.find((p) => p.id === ai?.default_provider)?.name ?? '—'})
                </option>
                {providers.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </Select>
            )}
            {running ? (
              <Button
                type="button"
                size="sm"
                variant="secondary"
                onClick={() => {
                  abort.current()
                }}
              >
                Cancel
              </Button>
            ) : (
              <Button type="button" size="sm" disabled={!idea.trim()} onClick={run}>
                Draft
              </Button>
            )}
            <Button
              type="button"
              size="sm"
              variant="tertiary"
              disabled={running}
              onClick={() => {
                setOpen(false)
              }}
            >
              Close
            </Button>
          </div>
          {assistant.status !== 'idle' && (
            <Activity
              assistant={assistant}
              elapsedMs={elapsedMs}
              providerLabel={chosen ? `${chosen.name} · ${chosen.model}` : null}
            />
          )}
        </>
      )}
    </section>
  )
}

const STEP_LABELS: Record<Step, string> = {
  resolve: 'Prepare',
  context: 'Context',
  wait: 'Wait for model',
  stream: 'Streaming',
  validate: 'Validate',
  done: 'Done',
}

/** The steps shown as a tracker; `context` folds into Prepare, `done` completes Validate. */
const TRACKER: Step[] = ['resolve', 'wait', 'stream', 'validate']

function Activity({
  assistant,
  elapsedMs,
  providerLabel,
}: {
  assistant: AssistantState
  elapsedMs: number
  providerLabel: string | null
}) {
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
  const stateOf = (step: Step) => {
    const index = TRACKER.indexOf(step)
    if (index < cursor) return 'done'
    if (index === cursor) return failed ? 'failed' : 'active'
    return 'todo'
  }
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
  ].filter(Boolean)
  const details = assistant.log.filter((s) => s.detail)
  const partial = assistant.result?.draft ?? assistant.partial

  return (
    <div className="ds-assist__activity mt2" role="status" aria-label="AI activity">
      <ol className="ds-tracker" aria-label="Steps">
        {TRACKER.map((step) => (
          <li key={step} className={cx('ds-tracker__step', `ds-tracker__step--${stateOf(step)}`)}>
            <span className="ds-tracker__dot" aria-hidden="true" />
            {STEP_LABELS[step]}
          </li>
        ))}
      </ol>
      <div className="flex items-center f6 mt1" style={{ gap: 8 }}>
        {running && <Spinner label="Drafting" />}
        <span className="truncate">{summary.join(' · ')}</span>
      </div>
      {partial && (
        <ul className="ds-fields" aria-label="Draft fields">
          <Field name="title" ok={!!partial.title} />
          <Field name="description" ok={!!partial.description} />
          <Field
            name="criteria"
            ok={(partial.acceptance_criteria?.length ?? 0) > 0}
            count={partial.acceptance_criteria?.length}
          />
          <Field name="priority" ok={!!partial.priority} />
          <Field name="points" ok={partial.points !== null && partial.points !== undefined} />
          <Field
            name="subtasks"
            ok={(partial.subtasks?.length ?? 0) > 0}
            count={partial.subtasks?.length}
          />
        </ul>
      )}
      {assistant.error && (
        <p className="f6 red mt1 mb0">
          <code>{assistant.error.code}</code> {assistant.error.message}
        </p>
      )}
      {assistant.status === 'done' && assistant.result && (
        <p className="f6 gray mt1 mb0">
          Drafted by {assistant.result.provider} ({assistant.result.model}) — review below, then
          Create.
          {assistant.sessionDrafts > 1 &&
            ` This session: ${String(assistant.sessionDrafts)} drafts, ${formatCost(assistant.sessionCostUSD)}.`}
        </p>
      )}
      {assistant.log.length > 0 && (
        <details className="f6 mt1">
          <summary className="gray">Details</summary>
          <table className="ds-phases">
            <tbody>
              {STEPS.filter((step) => durations[step] !== undefined && step !== 'done').map(
                (step) => (
                  <tr key={step}>
                    <th scope="row">{STEP_LABELS[step]}</th>
                    <td className="ds-phases__time">{seconds(durations[step] ?? 0)}</td>
                    <td className="ds-phases__detail">
                      {details
                        .filter((s) => s.step === step)
                        .map((s) => s.detail)
                        .join(' · ')}
                    </td>
                  </tr>
                ),
              )}
            </tbody>
          </table>
          <div className="flex mt1" style={{ gap: 8 }}>
            <Button
              type="button"
              size="sm"
              variant="tertiary"
              onClick={() => {
                void navigator.clipboard.writeText(logText(assistant, providerLabel))
              }}
            >
              Copy log
            </Button>
          </div>
          {assistant.text && (
            <details className="mt1">
              <summary className="gray">Raw output</summary>
              <pre className="ds-raw">{assistant.text}</pre>
            </details>
          )}
        </details>
      )}
    </div>
  )
}

function Field({ name, ok, count }: { name: string; ok: boolean; count?: number | undefined }) {
  return (
    <li className={cx('ds-fields__item', ok && 'ds-fields__item--ok')}>
      <span aria-hidden="true">{ok ? '✓' : '–'}</span> {name}
      {count !== undefined && count > 0 && ` ${String(count)}`}
    </li>
  )
}

function seconds(ms: number): string {
  return ms < 1000 ? `${String(ms)} ms` : `${(ms / 1000).toFixed(1)} s`
}
