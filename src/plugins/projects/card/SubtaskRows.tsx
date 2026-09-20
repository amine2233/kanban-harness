import { Button, Row } from '@mvp/design-system'
import type { CardFormAction, SubtaskRow } from './cardForm'

interface Props {
  rows: SubtaskRow[]
  includedCount: number
  dispatch: (action: CardFormAction) => void
}

/** The draft's proposed sub-tasks: tick, rename, drop, add — nothing is created until Create. */
export function SubtaskRows({ rows, includedCount, dispatch }: Props) {
  return (
    <fieldset className="ds-subtasks mb2">
      <legend className="f6 b">
        Sub-tasks ({String(includedCount)}/{String(rows.length)})
        <span className="gray fw4"> — the draft split this into separate pieces of work</span>
      </legend>
      {rows.map((row) => (
        <Row key={row.key} className="mb1">
          <input
            type="checkbox"
            aria-label={`Create sub-task ${row.title}`}
            checked={row.include}
            onChange={(e) => {
              dispatch({ type: 'subtask.include', key: row.key, value: e.target.checked })
            }}
          />
          <input
            className="hk-input flex-auto"
            aria-label={`Sub-task ${String(row.key + 1)} title`}
            value={row.title}
            maxLength={200}
            onChange={(e) => {
              dispatch({ type: 'subtask.title', key: row.key, value: e.target.value })
            }}
          />
          {row.points !== null && <span className="f6 gray">{String(row.points)} pt</span>}
          <Button
            type="button"
            size="sm"
            variant="tertiary"
            aria-label={`Remove sub-task ${row.title}`}
            onClick={() => {
              dispatch({ type: 'subtask.remove', key: row.key })
            }}
          >
            ×
          </Button>
        </Row>
      ))}
      <Button
        type="button"
        size="sm"
        variant="tertiary"
        onClick={() => {
          dispatch({ type: 'subtask.add' })
        }}
      >
        + Add a sub-task
      </Button>
    </fieldset>
  )
}
