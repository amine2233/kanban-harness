import { Input, Row, Select } from '@mvp/design-system'
import type { Board, CardPriority, CardStatus, Column } from '@mvp/kanban-model'
import type { CardForm, CardFormAction } from './cardForm'
import { DescriptionField } from './DescriptionField'

const PRIORITIES: CardPriority[] = ['low', 'medium', 'high', 'critical']
const STATUSES: CardStatus[] = ['todo', 'in_progress', 'blocked', 'done']

interface Props {
  form: CardForm
  dispatch: (action: CardFormAction) => void
  columns: Column[]
  boards: Board[]
  boardId: string
  /** Editing an existing card shows status, board, due date and points. */
  editing: boolean
  /** Saves a checklist toggle made in the description preview straight away. */
  onDescriptionToggle: ((value: string) => void) | undefined
  /** For AI description regeneration */
  scope?: { projectId: string; boardId: string }
}

export function CardFields({
  form,
  dispatch,
  columns,
  boards,
  boardId,
  editing,
  onDescriptionToggle,
  scope,
}: Props) {
  const set =
    (field: 'title' | 'columnId' | 'boardId' | 'dueDate' | 'points') =>
    (e: { target: { value: string } }) => {
      dispatch({ type: 'set', field, value: e.target.value })
    }
  return (
    <>
      <Input
        name="card-title"
        label="Title"
        value={form.title}
        required
        maxLength={200}
        onChange={set('title')}
        className="mb2"
      />
      <DescriptionField
        value={form.description}
        onChange={(value) => {
          dispatch({ type: 'set', field: 'description', value })
        }}
        onToggle={onDescriptionToggle}
        aiContext={
          scope && form.title.trim()
            ? { scope, title: form.title }
            : undefined
        }
      />
      <Row className="mb2">
        <Select
          name="card-priority"
          label="Priority"
          value={form.priority}
          className="flex-auto"
          onChange={(e) => {
            dispatch({ type: 'setPriority', value: e.target.value as CardPriority })
          }}
        >
          {PRIORITIES.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </Select>
        {editing && (
          <Select
            name="card-status"
            label="Status"
            value={form.status}
            className="flex-auto"
            onChange={(e) => {
              dispatch({ type: 'setStatus', value: e.target.value as CardStatus })
            }}
          >
            {STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </Select>
        )}
      </Row>
      <Row className="mb2">
        {editing && boards.length > 1 && (
          <Select
            name="card-board"
            label="Board"
            value={form.boardId}
            className="flex-auto"
            onChange={set('boardId')}
          >
            {boards.map((b) => (
              <option key={b.id} value={b.id}>
                {b.name}
              </option>
            ))}
          </Select>
        )}
        {form.boardId === boardId && (
          <Select
            name="card-column"
            label="Column"
            value={form.columnId}
            className="flex-auto"
            onChange={set('columnId')}
          >
            {columns.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </Select>
        )}
      </Row>
      {editing && (
        <Row className="mb2">
          <Input
            name="card-due"
            label="Due date"
            type="date"
            value={form.dueDate}
            className="flex-auto"
            onChange={set('dueDate')}
          />
          <Input
            name="card-points"
            label="Points"
            type="number"
            min={0}
            max={255}
            value={form.points}
            className="flex-auto"
            onChange={set('points')}
          />
        </Row>
      )}
    </>
  )
}
