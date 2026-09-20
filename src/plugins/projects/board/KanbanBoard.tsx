import { useMemo, useState } from 'react'
import { errorMessage } from '@/app/api'
import { Banner, Spinner } from '@mvp/design-system'
import { buildBoardIndex, groupCardsByColumn } from '@mvp/kanban-model'
import { BoardTabs } from './BoardTabs'
import { ColumnActions } from './ColumnActions'
import { KanbanColumn } from './KanbanColumn'
import { useListBoardsQuery, useListCardsQuery, useListColumnsQuery } from '../api/kanbanApi'

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
    <div className="ds-board-view">
      <BoardTabs
        projectId={projectId}
        boards={boardList}
        selectedId={boardId}
        onSelect={setSelected}
      />
      <BoardColumns projectId={projectId} boardId={boardId} />
    </div>
  )
}

function BoardColumns({ projectId, boardId }: { projectId: string; boardId: string }) {
  const scope = { projectId, boardId }
  const boards = useListBoardsQuery(projectId)
  const columns = useListColumnsQuery(scope)
  const cards = useListCardsQuery(scope)
  const columnList = useMemo(() => columns.data ?? [], [columns.data])
  const allCards = useMemo(() => cards.data ?? [], [cards.data])
  const index = useMemo(() => buildBoardIndex(allCards, columnList), [allCards, columnList])

  if (columns.isLoading || cards.isLoading) return <Spinner />
  const error = columns.error ?? cards.error
  if (error) {
    return (
      <Banner tone="danger" title="Cannot load board">
        {errorMessage(error)}
      </Banner>
    )
  }
  const grouped = groupCardsByColumn(columnList, allCards)

  return (
    <div className="ds-board">
      {columnList.map((column) => (
        <KanbanColumn
          key={column.id}
          scope={scope}
          column={column}
          columns={columnList}
          boards={boards.data ?? []}
          cards={grouped.get(column.id) ?? []}
          index={index}
          header={<ColumnActions scope={scope} column={column} columns={columnList} />}
        />
      ))}
    </div>
  )
}
