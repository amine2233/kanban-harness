import { useState, type SyntheticEvent } from 'react'
import { errorMessage } from '@/app/api'
import { Button, ConfirmModal, Input, Modal, Select, Textarea } from '@/design-system'
import { DraftWithAI } from './DraftWithAI'
import {
  useCreateCardMutation,
  useDeleteCardMutation,
  useUpdateCardMutation,
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
  /** Existing card to edit; omitted when creating. */
  card?: Card | undefined
  /** Column a new card lands in. */
  columnId?: string
  onClose: () => void
}

export function CardDialog({ scope, columns, boards, card, columnId, onClose }: Props) {
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
  const [confirmingDelete, setConfirmingDelete] = useState(false)
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
        {!card && (
          <DraftWithAI
            scope={scope}
            onDraft={(draft, description) => {
              setTitle(draft.title)
              setDescription(description)
              setPriority(draft.priority)
              if (draft.points !== null) setPoints(String(draft.points))
            }}
          />
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
        <Textarea
          name="card-description"
          label="Description"
          value={description}
          onChange={(e) => {
            setDescription(e.target.value)
          }}
          className="mb2"
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
              {card ? 'Save' : 'Create'}
            </Button>
          </span>
        </div>
      </form>
    </Modal>
  )
}
