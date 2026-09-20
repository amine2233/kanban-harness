import { useState, type DragEvent } from 'react'
import { Button, cx, Icon } from '@/design-system'
import { formatCost } from './assistantApi'
import { isTopLevel, neighbourColumns } from './board'
import { CardDialog } from './CardDialog'
import { CARD_MIME, draggedCard, serialiseCardDrag } from './dragAndDrop'
import { useMoveCardMutation, type Board, type Card as KanbanCard, type Column } from './kanbanApi'

interface Props {
  scope: { projectId: string; boardId: string }
  column: Column
  columns: Column[]
  boards: Board[]
  /** Cards whose column this is (top-level ones render here; sub-tasks render under their parent). */
  cards: KanbanCard[]
  /** Every card of the board, to nest sub-tasks under parents in this column. */
  allCards: KanbanCard[]
  header?: React.ReactNode
}

type Dialog = { kind: 'create' } | { kind: 'edit'; card: KanbanCard }

export function KanbanColumn({ scope, column, columns, boards, cards, allCards, header }: Props) {
  const [moveCard] = useMoveCardMutation()
  const [dialog, setDialog] = useState<Dialog>()
  const [dragOver, setDragOver] = useState(false)
  const { previous, next } = neighbourColumns(columns, column.id)
  const overLimit = column.wip_limit !== null && cards.length > column.wip_limit
  const roots = cards.filter((card) => isTopLevel(card, allCards))
  const childrenOf = (card: KanbanCard) =>
    allCards.filter((c) => c.parent_id === card.id).sort((a, b) => a.card_number - b.card_number)
  const columnName = (id: string) => columns.find((c) => c.id === id)?.name ?? '?'

  const onDragStart = (card: KanbanCard) => (event: DragEvent<HTMLLIElement>) => {
    event.dataTransfer.setData(CARD_MIME, serialiseCardDrag(card.id, card.column_id))
    event.dataTransfer.setData('text/plain', card.title)
    event.dataTransfer.effectAllowed = 'move'
    event.stopPropagation()
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

  const moves = (card: KanbanCard) => {
    const around = neighbourColumns(columns, card.column_id)
    const arrow = (target: Column, icon: 'arrowLeft' | 'arrowRight') => (
      <Button
        size="sm"
        variant="tertiary"
        aria-label={`Move ${card.title} to ${target.name}`}
        onClick={() => {
          void moveCard({ ...scope, cardId: card.id, columnId: target.id })
        }}
      >
        <Icon name={icon} size={14} />
      </Button>
    )
    return (
      <span className="ds-card__moves">
        {around.previous && arrow(around.previous, 'arrowLeft')}
        {around.next && arrow(around.next, 'arrowRight')}
      </span>
    )
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
        {roots.map((card) => {
          const children = childrenOf(card)
          const done = children.filter((c) => c.status === 'done').length
          return (
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
                  {card.ai_cost && (
                    <span
                      className="ds-card__cost"
                      title={`Drafted by ${card.ai_cost.provider} (${card.ai_cost.model})`}
                    >
                      {' '}
                      · ✨ {formatCost(card.ai_cost.cost_usd, card.ai_cost.estimated)}
                    </span>
                  )}
                  {children.length > 0 && (
                    <span
                      className={cx('ds-chip', done === children.length && 'ds-chip--done')}
                      aria-label={`${String(done)} of ${String(children.length)} sub-tasks done`}
                    >
                      ⌥ {String(done)}/{String(children.length)}
                    </span>
                  )}
                </span>
                {previous || next ? moves(card) : null}
              </footer>
              {children.length > 0 && (
                <ul className="ds-subtree list pl0 ma0" aria-label={`Sub-tasks of ${card.title}`}>
                  {children.map((child) => (
                    <li
                      key={child.id}
                      className={cx(
                        'ds-subtree__item',
                        child.status === 'done' && 'ds-subtree__item--done',
                      )}
                      draggable
                      aria-label={`${child.title} (sub-task, ${columnName(child.column_id)})`}
                      onDragStart={onDragStart(child)}
                    >
                      <span
                        className={`ds-priority ds-priority--${child.priority}`}
                        title={child.priority}
                      />
                      <button
                        type="button"
                        className="ds-subtree__title truncate"
                        aria-label={`Open ${child.title}`}
                        onClick={() => {
                          setDialog({ kind: 'edit', card: child })
                        }}
                      >
                        {child.title}
                      </button>
                      <span className="ds-subtree__key">
                        {child.prefix}-{child.card_number}
                      </span>
                      <span className={cx('ds-chip', child.status === 'done' && 'ds-chip--done')}>
                        {columnName(child.column_id)}
                      </span>
                      {moves(child)}
                    </li>
                  ))}
                </ul>
              )}
            </li>
          )
        })}
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
          key={dialog.kind === 'edit' ? dialog.card.id : 'create'}
          scope={scope}
          columns={columns}
          boards={boards}
          cards={allCards}
          card={dialog.kind === 'edit' ? dialog.card : undefined}
          columnId={column.id}
          onOpenCard={(card) => {
            setDialog({ kind: 'edit', card })
          }}
          onClose={() => {
            setDialog(undefined)
          }}
        />
      )}
    </section>
  )
}
