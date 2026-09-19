import { useState } from 'react'
import { errorMessage } from '@/app/api'
import { Banner, Select, Spinner } from '@/design-system'
import { groupCardsByColumn } from './board'
import { KanbanColumn } from './KanbanColumn'
import { useListBoardsQuery, useListCardsQuery, useListColumnsQuery } from './kanbanApi'

export function KanbanBoard({ projectId }: { projectId: string }) {
  const boards = useListBoardsQuery(projectId)
  const [selected, setSelected] = useState<string>()
  const boardId = selected ?? boards.data?.[0]?.id

  if (boards.isLoading) return <Spinner />
  if (boards.error) {
    return (
      <Banner tone="danger" title="Cannot load boards">
        {errorMessage(boards.error)}
      </Banner>
    )
  }
  if (!boardId) return <Banner tone="info" title="This project has no board yet" />

  return (
    <>
      {(boards.data?.length ?? 0) > 1 && (
        <Select
          name="board"
          label="Board"
          value={boardId}
          className="mb3 mw5"
          onChange={(e) => {
            setSelected(e.target.value)
          }}
        >
          {boards.data?.map((b) => (
            <option key={b.id} value={b.id}>
              {b.name}
            </option>
          ))}
        </Select>
      )}
      <BoardColumns projectId={projectId} boardId={boardId} />
    </>
  )
}

function BoardColumns({ projectId, boardId }: { projectId: string; boardId: string }) {
  const scope = { projectId, boardId }
  const columns = useListColumnsQuery(scope)
  const cards = useListCardsQuery(scope)

  if (columns.isLoading || cards.isLoading) return <Spinner />
  const error = columns.error ?? cards.error
  if (error) {
    return (
      <Banner tone="danger" title="Cannot load board">
        {errorMessage(error)}
      </Banner>
    )
  }
  const columnList = columns.data ?? []
  const grouped = groupCardsByColumn(columnList, cards.data ?? [])

  return (
    <div className="flex items-start overflow-x-auto" style={{ gap: 16 }}>
      {columnList.map((column) => (
        <KanbanColumn
          key={column.id}
          scope={scope}
          column={column}
          columns={columnList}
          cards={grouped.get(column.id) ?? []}
        />
      ))}
    </div>
  )
}
