import { useState, type SyntheticEvent } from 'react'
import { errorMessage } from '@/app/api'
import { Button, ConfirmModal, cx, Input, Modal, Select } from '@mvp/design-system'
import { formatCost, formatTokens } from '@mvp/kanban-model'
import { DescriptionField } from './DescriptionField'
import { DraftWithAI } from './DraftWithAI'
import {
  useCreateCardMutation,
  useDeleteCardMutation,
  useUpdateCardMutation,
  type AICost,
  type Board,
  type Card,
  type CardPatch,
  type CardPriority,
  type CardStatus,
  type Column,
} from './kanbanApi'

const PRIORITIES: CardPriority[] = ['low', 'medium', 'high', 'critical']
const STATUSES: CardStatus[] = ['todo', 'in_progress', 'blocked', 'done']

interface Props {
  scope: { projectId: string; boardId: string }
  columns: Column[]
  boards: Board[]
  /** Every card of the board, for the parent / children sections. */
  cards?: Card[]
  /** Existing card to edit; omitted when creating. */
  card?: Card | undefined
  /** Column a new card lands in. */
  columnId?: string
  /** Navigate to another card (a sub-task or the parent) in place of this one. */
  onOpenCard?: (card: Card) => void
  onClose: () => void
}

/** A proposed sub-task in the create form; unticked ones are not created. */
interface SubtaskRow {
  key: number
  title: string
  description: string | null
  points: number | null
  include: boolean
}

export function CardDialog({
  scope,
  columns,
  boards,
  cards = [],
  card,
  columnId,
  onOpenCard,
  onClose,
}: Props) {
  const [title, setTitle] = useState(card?.title ?? '')
  const [description, setDescription] = useState(card?.description ?? '')
  const [priority, setPriority] = useState<CardPriority>(card?.priority ?? 'medium')
  const [status, setStatus] = useState<CardStatus>(card?.status ?? 'todo')
  const [column, setColumn] = useState(card?.column_id ?? columnId ?? columns[0]?.id ?? '')
  const [board, setBoard] = useState(scope.boardId)
  const [dueDate, setDueDate] = useState(card?.due_date?.slice(0, 10) ?? '')
  const [points, setPoints] = useState(
    card?.points === null || card === undefined ? '' : String(card.points),
  )
  const [aiCost, setAiCost] = useState<AICost>()
  const [subtasks, setSubtasks] = useState<SubtaskRow[]>([])
  const [confirmingDelete, setConfirmingDelete] = useState(false)
  const parent = card?.parent_id ? cards.find((c) => c.id === card.parent_id) : undefined
  const children = card
    ? cards.filter((c) => c.parent_id === card.id).sort((a, b) => a.card_number - b.card_number)
    : []
  const columnName = (id: string) => columns.find((c) => c.id === id)?.name ?? '?'
  const included = subtasks.filter((s) => s.include && s.title.trim())
  const [createCard, create] = useCreateCardMutation()
  const [updateCard, update] = useUpdateCardMutation()
  const [deleteCard, remove] = useDeleteCardMutation()
  const error = create.error ?? update.error ?? remove.error
  const busy = create.isLoading || update.isLoading || remove.isLoading

  const submit = async (event: SyntheticEvent) => {
    event.preventDefault()
    const trimmed = title.trim()
    if (!trimmed) return
    const desc = description.trim() || null
    if (!card) {
      const result = await createCard({
        ...scope,
        columnId: column,
        title: trimmed,
        priority,
        description: desc,
        aiCost,
        subtasks: included.map((s) => ({
          title: s.title.trim(),
          description: s.description,
          points: s.points,
        })),
      })
      if (result.data) onClose()
      return
    }
    const patch: CardPatch = {
      title: trimmed,
      description: desc,
      priority,
      status,
      due_date: dueDate ? new Date(`${dueDate}T00:00:00Z`).toISOString() : null,
      points: points === '' ? null : Number(points),
    }
    if (board !== scope.boardId) patch.board_id = board
    else if (column !== card.column_id) patch.column_id = column
    const result = await updateCard({ ...scope, cardId: card.id, patch })
    if (result.data) onClose()
  }

  const confirmDelete = async () => {
    if (!card) return
    const result = await deleteCard({ ...scope, cardId: card.id })
    if (!('error' in result)) onClose()
  }

  if (confirmingDelete && card) {
    return (
      <ConfirmModal
        title={`Delete "${card.title}"?`}
        message="This cannot be undone."
        busy={remove.isLoading}
        onConfirm={() => {
          void confirmDelete()
        }}
        onClose={() => {
          setConfirmingDelete(false)
        }}
      />
    )
  }

  return (
    <Modal
      title={card ? `${card.prefix}-${String(card.card_number)}` : 'New card'}
      onClose={onClose}
    >
      <form
        onSubmit={(event) => {
          void submit(event)
        }}
      >
        {card?.ai_cost && (
          <p className="f6 gray mt0 mb2" aria-label="AI cost">
            ✨ Drafted by {card.ai_cost.provider} ({card.ai_cost.model}) ·{' '}
            {formatTokens(card.ai_cost)} ·{' '}
            {formatCost(card.ai_cost.cost_usd, card.ai_cost.estimated)}
          </p>
        )}
        {!card && (
          <DraftWithAI
            scope={scope}
            onDraft={(patch) => {
              if (patch.title !== undefined) setTitle(patch.title)
              if (patch.description !== undefined) setDescription(patch.description)
              if (patch.priority !== undefined) setPriority(patch.priority)
              if (patch.points !== undefined) setPoints(String(patch.points))
              if (patch.aiCost !== undefined) setAiCost(patch.aiCost)
              if (patch.subtasks !== undefined) {
                setSubtasks(patch.subtasks.map((s, key) => ({ key, ...s, include: true })))
              }
            }}
          />
        )}
        {parent && (
          <p className="f6 mt0 mb2">
            <span className="gray">Sub-task of </span>
            <button
              type="button"
              className="ds-link"
              onClick={() => {
                onOpenCard?.(parent)
              }}
            >
              {parent.prefix}-{String(parent.card_number)} {parent.title}
            </button>
          </p>
        )}
        <Input
          name="card-title"
          label="Title"
          value={title}
          required
          maxLength={200}
          onChange={(e) => {
            setTitle(e.target.value)
          }}
          className="mb2"
        />
        <DescriptionField
          value={description}
          onChange={setDescription}
          onToggle={
            card
              ? (next) => {
                  void updateCard({ ...scope, cardId: card.id, patch: { description: next } })
                }
              : undefined
          }
        />
        <div className="flex mb2" style={{ gap: 8 }}>
          <Select
            name="card-priority"
            label="Priority"
            value={priority}
            className="flex-auto"
            onChange={(e) => {
              setPriority(e.target.value as CardPriority)
            }}
          >
            {PRIORITIES.map((p) => (
              <option key={p} value={p}>
                {p}
              </option>
            ))}
          </Select>
          {card && (
            <Select
              name="card-status"
              label="Status"
              value={status}
              className="flex-auto"
              onChange={(e) => {
                setStatus(e.target.value as CardStatus)
              }}
            >
              {STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </Select>
          )}
        </div>
        <div className="flex mb2" style={{ gap: 8 }}>
          {card && boards.length > 1 && (
            <Select
              name="card-board"
              label="Board"
              value={board}
              className="flex-auto"
              onChange={(e) => {
                setBoard(e.target.value)
              }}
            >
              {boards.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </Select>
          )}
          {board === scope.boardId && (
            <Select
              name="card-column"
              label="Column"
              value={column}
              className="flex-auto"
              onChange={(e) => {
                setColumn(e.target.value)
              }}
            >
              {columns.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          )}
        </div>
        {card && (
          <div className="flex mb2" style={{ gap: 8 }}>
            <Input
              name="card-due"
              label="Due date"
              type="date"
              value={dueDate}
              className="flex-auto"
              onChange={(e) => {
                setDueDate(e.target.value)
              }}
            />
            <Input
              name="card-points"
              label="Points"
              type="number"
              min={0}
              max={255}
              value={points}
              className="flex-auto"
              onChange={(e) => {
                setPoints(e.target.value)
              }}
            />
          </div>
        )}
        {!card && subtasks.length > 0 && (
          <fieldset className="ds-subtasks mb2">
            <legend className="f6 b">
              Sub-tasks ({String(included.length)}/{String(subtasks.length)})
              <span className="gray fw4"> — the draft split this into separate pieces of work</span>
            </legend>
            {subtasks.map((row) => (
              <div key={row.key} className="flex items-center mb1" style={{ gap: 8 }}>
                <input
                  type="checkbox"
                  aria-label={`Create sub-task ${row.title}`}
                  checked={row.include}
                  onChange={(e) => {
                    setSubtasks((list) =>
                      list.map((s) =>
                        s.key === row.key ? { ...s, include: e.target.checked } : s,
                      ),
                    )
                  }}
                />
                <input
                  className="hk-input flex-auto"
                  aria-label={`Sub-task ${String(row.key + 1)} title`}
                  value={row.title}
                  maxLength={200}
                  onChange={(e) => {
                    setSubtasks((list) =>
                      list.map((s) => (s.key === row.key ? { ...s, title: e.target.value } : s)),
                    )
                  }}
                />
                {row.points !== null && <span className="f6 gray">{String(row.points)} pt</span>}
                <Button
                  type="button"
                  size="sm"
                  variant="tertiary"
                  aria-label={`Remove sub-task ${row.title}`}
                  onClick={() => {
                    setSubtasks((list) => list.filter((s) => s.key !== row.key))
                  }}
                >
                  ×
                </Button>
              </div>
            ))}
            <Button
              type="button"
              size="sm"
              variant="tertiary"
              onClick={() => {
                setSubtasks((list) => [
                  ...list,
                  {
                    key: (list.at(-1)?.key ?? -1) + 1,
                    title: '',
                    description: null,
                    points: null,
                    include: true,
                  },
                ])
              }}
            >
              + Add a sub-task
            </Button>
          </fieldset>
        )}
        {card && children.length > 0 && (
          <section className="ds-subtasks mb2" aria-label="Sub-tasks">
            <p className="f6 b mt0 mb1">
              Sub-tasks {String(children.filter((c) => c.status === 'done').length)}/
              {String(children.length)} done
            </p>
            <ul className="list pl0 ma0">
              {children.map((child) => (
                <li key={child.id} className="flex items-center f6 mb1" style={{ gap: 8 }}>
                  <span
                    className={`ds-priority ds-priority--${child.priority}`}
                    title={child.priority}
                  />
                  <button
                    type="button"
                    className="ds-link truncate flex-auto tl"
                    onClick={() => {
                      onOpenCard?.(child)
                    }}
                  >
                    {child.prefix}-{String(child.card_number)} {child.title}
                  </button>
                  <span className={cx('ds-chip', child.status === 'done' && 'ds-chip--done')}>
                    {columnName(child.column_id)}
                  </span>
                </li>
              ))}
            </ul>
          </section>
        )}
        {error && <p className="f6 red mt0 mb2">{errorMessage(error)}</p>}
        <div className="flex items-center justify-between">
          {card ? (
            <Button
              type="button"
              variant="danger"
              onClick={() => {
                setConfirmingDelete(true)
              }}
            >
              Delete
            </Button>
          ) : (
            <span />
          )}
          <span className="flex" style={{ gap: 8 }}>
            <Button type="button" variant="secondary" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit" disabled={busy}>
              {card
                ? 'Save'
                : included.length > 0
                  ? `Create 1 + ${String(included.length)} cards`
                  : 'Create'}
            </Button>
          </span>
        </div>
      </form>
    </Modal>
  )
}
