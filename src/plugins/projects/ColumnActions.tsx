import { useState } from 'react'
import { Button, ConfirmModal } from '@/design-system'
import { ColumnDialog } from './ColumnDialog'
import { useDeleteColumnMutation, useUpdateColumnMutation, type Column } from './kanbanApi'

interface Props {
  scope: { projectId: string; boardId: string }
  column: Column
  columns: Column[]
}

/** Header toolbar of a column: edit, move, delete. */
export function ColumnActions({ scope, column, columns }: Props) {
  const [dialog, setDialog] = useState<'edit' | 'delete'>()
  const [updateColumn] = useUpdateColumnMutation()
  const [deleteColumn, remove] = useDeleteColumnMutation()
  const index = columns.findIndex((c) => c.id === column.id)
  const close = () => {
    setDialog(undefined)
  }

  const move = (direction: -1 | 1) => {
    void updateColumn({ ...scope, columnId: column.id, position: index + direction })
  }

  const confirmDelete = async () => {
    const result = await deleteColumn({ ...scope, columnId: column.id })
    if (!('error' in result)) close()
  }

  return (
    <span className="flex" style={{ gap: 2 }}>
      <Button
        size="sm"
        variant="tertiary"
        aria-label={`Move column ${column.name} left`}
        disabled={index <= 0}
        onClick={() => {
          move(-1)
        }}
      >
        ←
      </Button>
      <Button
        size="sm"
        variant="tertiary"
        aria-label={`Move column ${column.name} right`}
        disabled={index >= columns.length - 1}
        onClick={() => {
          move(1)
        }}
      >
        →
      </Button>
      <Button
        size="sm"
        variant="tertiary"
        aria-label={`Edit column ${column.name}`}
        onClick={() => {
          setDialog('edit')
        }}
      >
        ✎
      </Button>
      <Button
        size="sm"
        variant="tertiary"
        aria-label={`Delete column ${column.name}`}
        disabled={columns.length <= 1}
        onClick={() => {
          setDialog('delete')
        }}
      >
        ×
      </Button>
      {dialog === 'edit' && <ColumnDialog scope={scope} column={column} onClose={close} />}
      {dialog === 'delete' && (
        <ConfirmModal
          title={`Delete column "${column.name}"?`}
          message="Cards in this column are deleted too."
          busy={remove.isLoading}
          onConfirm={() => {
            void confirmDelete()
          }}
          onClose={close}
        />
      )}
    </span>
  )
}
