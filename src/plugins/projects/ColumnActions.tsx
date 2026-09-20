import { useState } from 'react'
import { ConfirmModal, Menu } from '@/design-system'
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
    <>
      <Menu
        label={`Column ${column.name} actions`}
        items={[
          {
            label: 'Edit column',
            onSelect: () => {
              setDialog('edit')
            },
          },
          {
            label: 'Move left',
            disabled: index <= 0,
            onSelect: () => {
              move(-1)
            },
          },
          {
            label: 'Move right',
            disabled: index >= columns.length - 1,
            onSelect: () => {
              move(1)
            },
          },
          {
            label: 'Delete column',
            danger: true,
            separated: true,
            disabled: columns.length <= 1,
            onSelect: () => {
              setDialog('delete')
            },
          },
        ]}
      />
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
    </>
  )
}
