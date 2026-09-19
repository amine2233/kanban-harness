import { useState, type SyntheticEvent } from 'react'
import { Badge, Button, Card, Input } from '@/design-system'
import { neighbourColumns, PRIORITY_BADGE } from './board'
import {
  useCreateCardMutation,
  useDeleteCardMutation,
  useMoveCardMutation,
  type Card as KanbanCard,
  type Column,
} from './kanbanApi'

interface Props {
  scope: { projectId: string; boardId: string }
  column: Column
  columns: Column[]
  cards: KanbanCard[]
}

export function KanbanColumn({ scope, column, columns, cards }: Props) {
  const [createCard, { isLoading: creating }] = useCreateCardMutation()
  const [moveCard] = useMoveCardMutation()
  const [deleteCard] = useDeleteCardMutation()
  const [title, setTitle] = useState('')
  const { previous, next } = neighbourColumns(columns, column.id)
  const overLimit = column.wip_limit !== null && cards.length > column.wip_limit

  const submit = async (event: SyntheticEvent) => {
    event.preventDefault()
    const trimmed = title.trim()
    if (!trimmed) return
    const result = await createCard({
      ...scope,
      columnId: column.id,
      title: trimmed,
      priority: 'medium',
    })
    if (result.data) setTitle('')
  }

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
    >
      <ul className="list pl0 ma0">
        {cards.map((card) => (
          <li key={card.id} className="pa2 mb2 br2 bg-lightest-silver shadow-outer-1">
            <div className="flex items-start justify-between" style={{ gap: 8 }}>
              <span className="near-black">{card.title}</span>
              <Badge variant={PRIORITY_BADGE[card.priority]}>{card.priority}</Badge>
            </div>
            <div className="flex items-center justify-between mt2">
              <span className="f7 gray">
                {card.prefix}-{card.card_number}
              </span>
              <span className="flex" style={{ gap: 4 }}>
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
                <Button
                  size="sm"
                  variant="danger"
                  aria-label={`Delete ${card.title}`}
                  onClick={() => {
                    void deleteCard({ ...scope, cardId: card.id })
                  }}
                >
                  ×
                </Button>
              </span>
            </div>
          </li>
        ))}
      </ul>
      <form
        onSubmit={(event) => {
          void submit(event)
        }}
        className="flex items-center mt2"
        style={{ gap: 8 }}
      >
        <Input
          name={`new-card-${column.id}`}
          aria-label={`New card in ${column.name}`}
          placeholder="Add a card…"
          value={title}
          maxLength={200}
          onChange={(e) => {
            setTitle(e.target.value)
          }}
          className="flex-auto"
        />
        <Button type="submit" size="sm" variant="secondary" disabled={creating}>
          Add
        </Button>
      </form>
    </Card>
  )
}
