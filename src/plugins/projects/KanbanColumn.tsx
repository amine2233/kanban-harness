import { useState, type DragEvent } from 'react'
import { cx, Icon } from '@/design-system'
import { CardDialog } from './CardDialog'
import { CARD_MIME, draggedCard, serialiseCardDrag } from './dragAndDrop'
import { KanbanCard } from './KanbanCard'
import { useMoveCardMutation, type Board, type Card, type Column } from './kanbanApi'

interface Props {
  scope: { projectId: string; boardId: string }
  column: Column
  columns: Column[]
  boards: Board[]
  /** Cards whose column this is (top-level ones render here; sub-tasks render under their parent). */
  cards: Card[]
  /** Every card of the board, to nest sub-tasks under parents in this column. */
  allCards: Card[]
  header?: React.ReactNode
}

type Dialog = { kind: 'create' } | { kind: 'edit'; card: Card }

export function KanbanColumn({ scope, column, columns, boards, cards, allCards, header }: Props) {
  const [moveCard] = useMoveCardMutation()
  const [dialog, setDialog] = useState<Dialog>()
  const [dragOver, setDragOver] = useState(false)
  const overLimit = column.wip_limit !== null && cards.length > column.wip_limit
  const childrenOf = (card: Card) =>
    allCards.filter((c) => c.parent_id === card.id).sort((a, b) => a.card_number - b.card_number)
  const parentOf = (card: Card) =>
    card.parent_id ? allCards.find((c) => c.id === card.parent_id) : undefined
  const columnName = (id: string) => columns.find((c) => c.id === id)?.name ?? '?'

  const onDragStart = (card: Card) => (event: DragEvent<HTMLLIElement>) => {
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

  const open = (card: Card) => {
    setDialog({ kind: 'edit', card })
  }
  const move = (card: Card, columnId: string) => {
    void moveCard({ ...scope, cardId: card.id, columnId })
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
        {cards.map((card) => {
          const children = childrenOf(card)
          const done = children.filter((c) => c.status === 'done').length
          return (
            <KanbanCard
              key={card.id}
              card={card}
              columns={columns}
              parent={parentOf(card)}
              onOpen={open}
              onMove={move}
              onDragStart={onDragStart}
            >
              {children.length > 0 && (
                <section className="ds-subtree" aria-label={`Sub-tasks of ${card.title}`}>
                  <header className="ds-subtree__header">
                    <Icon name="subtasks" size={12} />
                    <span
                      aria-label={`${String(done)} of ${String(children.length)} sub-tasks done`}
                    >
                      Sub-tasks {String(done)}/{String(children.length)}
                    </span>
                    <span className="ds-subtree__bar" aria-hidden="true">
                      <span style={{ width: `${String((done / children.length) * 100)}%` }} />
                    </span>
                  </header>
                  <ul className="list pl0 ma0">
                    {children.map((child) => (
                      <li
                        key={child.id}
                        className={cx(
                          'ds-subtree__row',
                          child.status === 'done' && 'ds-subtree__row--done',
                        )}
                        aria-label={`${child.title} (sub-task, ${columnName(child.column_id)})`}
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
                            open(child)
                          }}
                        >
                          <span className="ds-subtree__key">
                            {child.prefix}-{child.card_number}
                          </span>{' '}
                          {child.title}
                        </button>
                        <span className={cx('ds-chip', child.status === 'done' && 'ds-chip--done')}>
                          {columnName(child.column_id)}
                        </span>
                      </li>
                    ))}
                  </ul>
                </section>
              )}
            </KanbanCard>
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
          onOpenCard={open}
          onClose={() => {
            setDialog(undefined)
          }}
        />
      )}
    </section>
  )
}
