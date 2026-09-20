import { useReducer, useState, type SyntheticEvent } from 'react'
import { DraftWithAI } from '../assistant/DraftWithAI'
import { CardFields } from './CardFields'
import {
  cardFormReducer,
  includedSubtasks,
  initialCardForm,
  toCreateRequest,
  toPatch,
} from './cardForm'
import { CardRelations } from './CardRelations'
import { SubtaskRows } from './SubtaskRows'
import {
  type Board,
  type Card,
  type Column,
  errorMessage,
  useCreateCardMutation,
  useDeleteCardMutation,
  useUpdateCardMutation,
} from '@mvp/state'
import { Button, ConfirmModal, Modal, Row } from '@mvp/design-system'
import { type BoardIndex, formatCost, formatTokens } from '@mvp/kanban-model'

interface Props {
  scope: { projectId: string; boardId: string }
  columns: Column[]
  boards: Board[]
  /** Derived board data (hierarchy, names); needed to show relations of an existing card. */
  index?: BoardIndex
  /** Existing card to edit; omitted when creating. */
  card?: Card | undefined
  /** Column a new card lands in. */
  columnId?: string
  /** Navigate to another card (a sub-task or the parent) in place of this one. */
  onOpenCard?: (card: Card) => void
  onClose: () => void
}

/** Create or edit one card. Owns the mutations; the form itself is `cardForm.ts`. */
export function CardDialog({
  scope,
  columns,
  boards,
  index,
  card,
  columnId,
  onOpenCard,
  onClose,
}: Props) {
  const [form, dispatch] = useReducer(cardFormReducer, undefined, () =>
    initialCardForm(card, scope, columns, columnId),
  )
  const [confirmingDelete, setConfirmingDelete] = useState(false)
  const [createCard, create] = useCreateCardMutation()
  const [updateCard, update] = useUpdateCardMutation()
  const [deleteCard, remove] = useDeleteCardMutation()
  const error = create.error ?? update.error ?? remove.error
  const busy = create.isLoading || update.isLoading || remove.isLoading
  const included = includedSubtasks(form).length

  const submit = async (event: SyntheticEvent) => {
    event.preventDefault()
    if (!card) {
      const request = toCreateRequest(form)
      if (!request) return
      const result = await createCard({ ...scope, ...request })
      if (result.data) onClose()
      return
    }
    const patch = toPatch(form, card, scope)
    if (!patch) return
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
              dispatch({ type: 'applyDraft', patch })
            }}
          />
        )}
        {card && index && <CardRelations card={card} index={index} onOpenCard={onOpenCard} />}
        <CardFields
          form={form}
          dispatch={dispatch}
          columns={columns}
          boards={boards}
          boardId={scope.boardId}
          editing={card !== undefined}
          onDescriptionToggle={
            card
              ? (next) => {
                  void updateCard({ ...scope, cardId: card.id, patch: { description: next } })
                }
              : undefined
          }
        />
        {!card && form.subtasks.length > 0 && (
          <SubtaskRows rows={form.subtasks} includedCount={included} dispatch={dispatch} />
        )}
        {error && <p className="f6 red mt0 mb2">{errorMessage(error)}</p>}
        <Row className="justify-between">
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
          <Row>
            <Button type="button" variant="secondary" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit" disabled={busy}>
              {card ? 'Save' : included > 0 ? `Create 1 + ${String(included)} cards` : 'Create'}
            </Button>
          </Row>
        </Row>
      </form>
    </Modal>
  )
}
