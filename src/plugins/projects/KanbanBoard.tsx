import { useState } from 'react'
import { errorMessage } from '@/app/api'
import { Banner, Button, Spinner } from '@/design-system'
import { groupCardsByColumn } from './board'
import { BoardTabs } from './BoardTabs'
import { ColumnActions } from './ColumnActions'
import { ColumnDialog } from './ColumnDialog'
import { KanbanColumn } from './KanbanColumn'
import { useListBoardsQuery, useListCardsQuery, useListColumnsQuery } from './kanbanApi'

export function KanbanBoard({ projectId }: { projectId: string }) {
  const boards = useListBoardsQuery(projectId)
  const [selected, setSelected] = useState<string>()
  const boardList = boards.data ?? []
  const boardId = boardList.some((b) => b.id === selected) ? selected : boardList[0]?.id

  if (boards.isLoading) return <Spinner />
  if (boards.error) {
    return (
      <Banner tone="danger" title="Cannot load boards">
        {errorMessage(boards.error)}
      </Banner>
    )
  }
  if (!boardId) {
    return (
      <>
        <Banner tone="info" title="This project has no board yet" className="mb3" />
        <BoardTabs projectId={projectId} boards={[]} selectedId="" onSelect={setSelected} />
      </>
    )
  }

  return (
    <>
      <BoardTabs
        projectId={projectId}
        boards={boardList}
        selectedId={boardId}
        onSelect={setSelected}
      />
      <BoardColumns projectId={projectId} boardId={boardId} />
    </>
  )
}

function BoardColumns({ projectId, boardId }: { projectId: string; boardId: string }) {
  const scope = { projectId, boardId }
  const boards = useListBoardsQuery(projectId)
  const columns = useListColumnsQuery(scope)
  const cards = useListCardsQuery(scope)
  const [adding, setAdding] = useState(false)

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
          boards={boards.data ?? []}
          cards={grouped.get(column.id) ?? []}
          header={<ColumnActions scope={scope} column={column} columns={columnList} />}
        />
      ))}
      <Button
        variant="secondary"
        className="flex-none"
        onClick={() => {
          setAdding(true)
        }}
      >
        + Add column
      </Button>
      {adding && (
        <ColumnDialog
          scope={scope}
          onClose={() => {
            setAdding(false)
          }}
        />
      )}
    </div>
  )
}
