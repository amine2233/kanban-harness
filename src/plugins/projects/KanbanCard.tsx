import type { DragEvent, ReactNode } from 'react'
import { Button, checklistProgress, cx, Icon } from '@/design-system'
import { formatCost } from './assistantApi'
import { neighbourColumns } from './board'
import type { Card, Column } from './kanbanApi'

interface Props {
  card: Card
  columns: Column[]
  /** `mini`: a sub-task tile inside its parent. */
  variant?: 'card' | 'mini'
  onOpen: (card: Card) => void
  onMove: (card: Card, columnId: string) => void
  onDragStart: (card: Card) => (event: DragEvent<HTMLLIElement>) => void
  /** Rendered below the meta row (the sub-task tree of a parent). */
  children?: ReactNode
}

/** A card on the board: title, the facts that matter at a glance, never the whole description. */
export function KanbanCard({
  card,
  columns,
  variant = 'card',
  onOpen,
  onMove,
  onDragStart,
  children,
}: Props) {
  const mini = variant === 'mini'
  const { previous, next } = neighbourColumns(columns, card.column_id)
  const column = columns.find((c) => c.id === card.column_id)
  const checklist = checklistProgress(card.description)
  const due = card.due_date ? dueLabel(card.due_date, card.status === 'done') : null

  return (
    <li
      className={cx(mini ? 'ds-mini' : 'ds-card', `ds-priority-edge--${card.priority}`)}
      draggable
      aria-label={
        mini
          ? `${card.title} (sub-task, ${column?.name ?? '?'})`
          : `${card.title} (${card.priority})`
      }
      onDragStart={onDragStart(card)}
    >
      <button
        type="button"
        className={mini ? 'ds-mini__body' : 'ds-card__body'}
        aria-label={`Open ${card.title}`}
        onClick={() => {
          onOpen(card)
        }}
      >
        <span className={mini ? 'ds-mini__title' : 'ds-card__title'}>{card.title}</span>
      </button>
      <footer className={mini ? 'ds-mini__footer' : 'ds-card__footer'}>
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
          {!checklist && card.description && !mini && (
            <span className="ds-fact" title="Has a description" aria-label="Has a description">
              ≡
            </span>
          )}
          {card.ai_cost && !mini && (
            <span
              className="ds-fact ds-fact--ai"
              title={`Drafted by ${card.ai_cost.provider} (${card.ai_cost.model})`}
            >
              ✨ {formatCost(card.ai_cost.cost_usd, card.ai_cost.estimated)}
            </span>
          )}
        </span>
        {mini && (
          <span className={cx('ds-chip', card.status === 'done' && 'ds-chip--done')}>
            {column?.name ?? '?'}
          </span>
        )}
        {(previous ?? next) && (
          <span className="ds-card__moves">
            {previous && (
              <Button
                size="sm"
                variant="tertiary"
                aria-label={`Move ${card.title} to ${previous.name}`}
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
