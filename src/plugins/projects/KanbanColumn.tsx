import { useState } from 'react'
import { Badge, Button, Card } from '@/design-system'
import { neighbourColumns, PRIORITY_BADGE } from './board'
import { CardDialog } from './CardDialog'
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
  const { previous, next } = neighbourColumns(columns, column.id)
  const overLimit = column.wip_limit !== null && cards.length > column.wip_limit

  return (
    <Card
      className="flex-none"
      style={{ width: 280 }}
      aria-label={column.name}
      title={
        <span className="flex items-center" style={{ gap: 8 }}>
          {column.name}
          <Badge variant={overLimit ? 'alpha' : 'outline'}>
            {column.wip_limit === null
              ? String(cards.length)
              : `${String(cards.length)}/${String(column.wip_limit)}`}
          </Badge>
        </span>
      }
      actions={header}
    >
      <ul className="list pl0 ma0">
        {cards.map((card) => (
          <li key={card.id} className="pa2 mb2 br2 bg-lightest-silver shadow-outer-1">
            <button
              type="button"
              className="ds-card-title"
              aria-label={`Open ${card.title}`}
              onClick={() => {
                setDialog({ kind: 'edit', card })
              }}
            >
              <span className="near-black">{card.title}</span>
              <Badge variant={PRIORITY_BADGE[card.priority]}>{card.priority}</Badge>
            </button>
            <div className="flex items-center justify-between mt2" style={{ gap: 4 }}>
              <span className="f7 gray truncate">
                {card.prefix}-{card.card_number}
                {card.due_date && ` · due ${card.due_date.slice(0, 10)}`}
                {card.points !== null && ` · ${String(card.points)} pt`}
              </span>
              <span className="flex flex-none" style={{ gap: 4 }}>
                {previous && (
                  <Button
                    size="sm"
                    variant="tertiary"
                    aria-label={`Move ${card.title} to ${previous.name}`}
                    onClick={() => {
                      void moveCard({ ...scope, cardId: card.id, columnId: previous.id })
                    }}
                  >
                    ←
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
                    →
                  </Button>
                )}
              </span>
            </div>
          </li>
        ))}
      </ul>
      <Button
        variant="secondary"
        size="sm"
        className="w-100 mt2"
        aria-label={`Add card to ${column.name}`}
        onClick={() => {
          setDialog({ kind: 'create' })
        }}
      >
        + Add card
      </Button>
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
    </Card>
  )
}
