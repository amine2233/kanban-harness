import { Button, cx, Row, Spinner } from '@mvp/design-system'
import { formatCost } from '@mvp/kanban-model'
import { logText } from './assistantLog'
import { STEPS, type AssistantState } from './assistantSlice'
import { seconds, STEP_LABELS, trackerState } from './tracker'

/** What the assistant is doing, at three levels: tracker, summary, details. */
export function ActivityPanel({
  assistant,
  elapsedMs,
  providerLabel,
}: {
  assistant: AssistantState
  elapsedMs: number
  providerLabel: string | null
}) {
  const running = assistant.status === 'running'
  const { steps, summary, durations } = trackerState(assistant, elapsedMs, providerLabel)
  const details = assistant.log.filter((s) => s.detail)
  const partial = assistant.result?.draft ?? assistant.partial

  return (
    <div className="ds-assist__activity mt2" role="status" aria-label="AI activity">
      <ol className="ds-tracker" aria-label="Steps">
        {steps.map(({ step, label, state }) => (
          <li key={step} className={cx('ds-tracker__step', `ds-tracker__step--${state}`)}>
            <span className="ds-tracker__dot" aria-hidden="true" />
            {label}
          </li>
        ))}
      </ol>
      <Row className="f6 mt1">
        {running && <Spinner label="Drafting" />}
        <span className="truncate">{summary}</span>
      </Row>
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
          <Row className="mt1">
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
          </Row>
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
