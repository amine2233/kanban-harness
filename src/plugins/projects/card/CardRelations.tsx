import { cx, Row } from '@mvp/design-system'
import type { BoardIndex, Card } from '@mvp/kanban-model'

interface Props {
  card: Card
  index: BoardIndex
  onOpenCard: ((card: Card) => void) | undefined
}

/** Where the card sits in the hierarchy: its parent above, its sub-tasks below. */
export function CardRelations({ card, index, onOpenCard }: Props) {
  const parent = index.parentOf(card)
  const children = index.childrenOf(card)
  const progress = index.progress(card)
  return (
    <>
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
      {children.length > 0 && (
        <section className="ds-subtasks mb2" aria-label="Sub-tasks">
          <p className="f6 b mt0 mb1">
            Sub-tasks {String(progress.done)}/{String(progress.total)} done
          </p>
          <ul className="list pl0 ma0">
            {children.map((child) => (
              <Row as="li" key={child.id} className="f6 mb1">
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
                  {index.columnName(child.column_id)}
                </span>
              </Row>
            ))}
          </ul>
        </section>
      )}
    </>
  )
}
