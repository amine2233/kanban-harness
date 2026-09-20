import { useState, type DragEvent } from 'react'
import { Button, cx, Icon } from '@/design-system'
import { neighbourColumns } from './board'
import { CardDialog } from './CardDialog'
import { CARD_MIME, draggedCard, serialiseCardDrag } from './dragAndDrop'
import { useMoveCardMutation, type Board, type Card as KanbanCard, type Column } from './kanbanApi'

interface Props {
  scope: { projectId: string; boardId: string }
  column: Column
  columns: Column[]
  boards: Board[]
  cards: KanbanCard[]
  header?: React.ReactNode
}

type Dialog = { kind: 'create' } | { kind: 'edit'; card: KanbanCard }

export function KanbanColumn({ scope, column, columns, boards, cards, header }: Props) {
  const [moveCard] = useMoveCardMutation()
  const [dialog, setDialog] = useState<Dialog>()
  const [dragOver, setDragOver] = useState(false)
  const { previous, next } = neighbourColumns(columns, column.id)
  const overLimit = column.wip_limit !== null && cards.length > column.wip_limit

  const onDragStart = (card: KanbanCard) => (event: DragEvent<HTMLLIElement>) => {
    event.dataTransfer.setData(CARD_MIME, serialiseCardDrag(card.id, card.column_id))
    event.dataTransfer.setData('text/plain', card.title)
    event.dataTransfer.effectAllowed = 'move'
  }

  const onDragOver = (event: DragEvent<HTMLElement>) => {
    if (!event.dataTransfer.types.includes(CARD_MIME)) return
    event.preventDefault()
    event.dataTransfer.dropEffect = 'move'
    setDragOver(true)
  }

  const onDrop = (event: DragEvent<HTMLElement>) => {
    event.preventDefault()
    setDragOver(false)
    const dragged = draggedCard(event.dataTransfer)
    if (!dragged || dragged.columnId === column.id) return
    void moveCard({ ...scope, cardId: dragged.cardId, columnId: column.id })
  }

  return (
    <section
      className={cx(
        'ds-column',
        dragOver && 'ds-column--drag-over',
        overLimit && 'ds-column--over-limit',
      )}
      aria-label={column.name}
      onDragOver={onDragOver}
      onDragLeave={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setDragOver(false)
      }}
      onDrop={onDrop}
    >
      <header className="ds-column__header">
        <h2 className="ds-column__title truncate">{column.name}</h2>
        <span className="ds-column__count" aria-label={`${String(cards.length)} cards`}>
          {column.wip_limit === null
            ? String(cards.length)
            : `${String(cards.length)} / ${String(column.wip_limit)}`}
        </span>
        <span className="ds-column__actions">{header}</span>
      </header>
      <ul className="ds-column__cards list pl0 ma0">
        {cards.map((card) => (
          <li
            key={card.id}
            className={cx('ds-card', `ds-card--${card.priority}`)}
            draggable
            aria-label={`${card.title} (${card.priority})`}
            onDragStart={onDragStart(card)}
          >
            <button
              type="button"
              className="ds-card__body"
              aria-label={`Open ${card.title}`}
              onClick={() => {
                setDialog({ kind: 'edit', card })
              }}
            >
              <span className="ds-card__title">{card.title}</span>
              {card.description && <span className="ds-card__snippet">{card.description}</span>}
            </button>
            <footer className="ds-card__footer">
              <span className="ds-card__meta truncate">
                <span
                  className={`ds-priority ds-priority--${card.priority}`}
                  title={card.priority}
                />
                {card.prefix}-{card.card_number}
                {card.due_date && ` · ${card.due_date.slice(0, 10)}`}
                {card.points !== null && ` · ${String(card.points)} pt`}
              </span>
              <span className="ds-card__moves">
                {previous && (
                  <Button
                    size="sm"
                    variant="tertiary"
                    aria-label={`Move ${card.title} to ${previous.name}`}
                    onClick={() => {
                      void moveCard({ ...scope, cardId: card.id, columnId: previous.id })
                    }}
                  >
                    <Icon name="arrowLeft" size={14} />
                  </Button>
                )}
                {next && (
                  <Button
                    size="sm"
                    variant="tertiary"
                    aria-label={`Move ${card.title} to ${next.name}`}
                    onClick={() => {
                      void moveCard({ ...scope, cardId: card.id, columnId: next.id })
                    }}
                  >
                    <Icon name="arrowRight" size={14} />
                  </Button>
                )}
              </span>
            </footer>
          </li>
        ))}
      </ul>
      <button
        type="button"
        className="ds-column__add"
        aria-label={`Add card to ${column.name}`}
        onClick={() => {
          setDialog({ kind: 'create' })
        }}
      >
        <Icon name="plus" size={14} /> Add card
      </button>
      {dialog && (
        <CardDialog
          scope={scope}
          columns={columns}
          boards={boards}
          card={dialog.kind === 'edit' ? dialog.card : undefined}
          columnId={column.id}
          onClose={() => {
            setDialog(undefined)
          }}
        />
      )}
    </section>
  )
}
