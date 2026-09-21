import type { DragEvent, ReactNode } from 'react'
import { Button, cx, Icon } from '@mvp/design-system'
import {
  formatCost,
  neighbourColumns,
  type BoardIndex,
  type Card,
  type Column,
} from '@mvp/kanban-model'

interface Props {
  card: Card
  columns: Column[]
  index: BoardIndex
  onOpen: (card: Card) => void
  onMove: (card: Card, columnId: string) => void
  onDragStart: (card: Card) => (event: DragEvent<HTMLLIElement>) => void
  /** Rendered below the meta row (the sub-task tree of a parent). */
  children?: ReactNode
}

/** A card on the board: title, the facts that matter at a glance, never the whole description. */
export function KanbanCard({ card, columns, index, onOpen, onMove, onDragStart, children }: Props) {
  const { previous, next } = neighbourColumns(columns, card.column_id)
  const parent = index.parentOf(card)
  const checklist = index.checklist(card)
  const due = card.due_date ? dueLabel(card.due_date, card.status === 'done') : null
  const color = index.color(card)

  return (
    <li
      className="ds-card"
      style={{ borderLeftColor: color }}
      draggable
      aria-label={
        parent
          ? `${card.title} (sub-task of ${parent.prefix}-${String(parent.card_number)})`
          : `${card.title} (${card.priority})`
      }
      onDragStart={onDragStart(card)}
    >
      {parent && (
        <button
          type="button"
          className="ds-card__parent"
          style={{ color }}
          aria-label={`Open parent ${parent.title}`}
          title={parent.title}
          draggable={false}
          onClick={() => {
            onOpen(parent)
          }}
        >
          <Icon name="subtasks" size={11} /> {parent.prefix}-{parent.card_number}
          <span className="truncate"> · {parent.title}</span>
        </button>
      )}
      <button
        type="button"
        className="ds-card__body"
        aria-label={`Open ${card.title}`}
        draggable={false}
        onClick={() => {
          onOpen(card)
        }}
      >
        <span className="ds-card__title">{card.title}</span>
      </button>
      <footer className="ds-card__footer">
        <span className="ds-card__meta">
          <span className={`ds-priority ds-priority--${card.priority}`} title={card.priority} />
          <span className="ds-card__key">
            {card.prefix}-{card.card_number}
          </span>
          {card.points !== null && <span className="ds-fact">{String(card.points)} pt</span>}
          {due && (
            <span
              className={cx('ds-fact', due.overdue && 'ds-fact--overdue')}
              title={card.due_date ?? ''}
            >
              <Icon name="calendar" size={11} /> {due.label}
            </span>
          )}
          {checklist && (
            <span
              className={cx('ds-fact', checklist.done === checklist.total && 'ds-fact--done')}
              aria-label={`${String(checklist.done)} of ${String(checklist.total)} criteria done`}
            >
              ☑ {String(checklist.done)}/{String(checklist.total)}
            </span>
          )}
          {!checklist && card.description && (
            <span className="ds-fact" title="Has a description" aria-label="Has a description">
              ≡
            </span>
          )}
          {card.ai_cost && (
            <span
              className="ds-fact ds-fact--ai"
              title={`Drafted by ${card.ai_cost.provider} (${card.ai_cost.model})`}
            >
              ✨ {formatCost(card.ai_cost.cost_usd, card.ai_cost.estimated)}
            </span>
          )}
        </span>
        {(previous ?? next) && (
          <span className="ds-card__moves">
            {previous && (
              <Button
                size="sm"
                variant="tertiary"
                aria-label={`Move ${card.title} to ${previous.name}`}
                draggable={false}
                onClick={() => {
                  onMove(card, previous.id)
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
                draggable={false}
                onClick={() => {
                  onMove(card, next.id)
                }}
              >
                <Icon name="arrowRight" size={14} />
              </Button>
            )}
          </span>
        )}
      </footer>
      {children}
    </li>
  )
}

function dueLabel(iso: string, done: boolean): { label: string; overdue: boolean } {
  const date = new Date(iso)
  const label = date.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  return { label, overdue: !done && date < today }
}
