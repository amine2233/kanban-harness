import { useState, type SyntheticEvent } from 'react'
import { errorMessage } from '@/app/api'
import { Button, ConfirmModal, Input, Menu, Modal } from '@mvp/design-system'
import { ColumnDialog } from './ColumnDialog'
import {
  useCloneBoardMutation,
  useCreateBoardMutation,
  useDeleteBoardMutation,
  useUpdateBoardMutation,
  type Board,
} from './kanbanApi'

interface Props {
  projectId: string
  boards: Board[]
  selectedId: string
  onSelect: (boardId: string) => void
}

type Dialog =
  | { kind: 'create' }
  | { kind: 'rename'; board: Board }
  | { kind: 'delete'; board: Board }
  | { kind: 'add-column'; board: Board }

export function BoardTabs({ projectId, boards, selectedId, onSelect }: Props) {
  const [dialog, setDialog] = useState<Dialog>()
  const [updateBoard] = useUpdateBoardMutation()
  const [cloneBoard, clone] = useCloneBoardMutation()
  const [deleteBoard, remove] = useDeleteBoardMutation()
  const selected = boards.find((b) => b.id === selectedId)
  const index = boards.findIndex((b) => b.id === selectedId)
  const close = () => {
    setDialog(undefined)
  }

  const move = (direction: -1 | 1) => {
    if (!selected) return
    onSelect(selected.id)
    void updateBoard({ projectId, boardId: selected.id, position: index + direction })
  }

  const duplicate = async () => {
    if (!selected) return
    const result = await cloneBoard({ projectId, boardId: selected.id })
    if (result.data) onSelect(result.data.id)
  }

  const confirmDelete = async () => {
    if (dialog?.kind !== 'delete') return
    const result = await deleteBoard({ projectId, boardId: dialog.board.id })
    if (!('error' in result)) {
      close()
      const next = boards.find((b) => b.id !== dialog.board.id)
      if (next) onSelect(next.id)
    }
  }

  return (
    <>
      <div className="ds-tabs-row flex items-center mb3" style={{ gap: 8 }}>
        <div className="ds-tabs flex-auto" role="tablist" aria-label="Boards">
          {boards.map((board) => (
            <button
              key={board.id}
              type="button"
              role="tab"
              aria-selected={board.id === selectedId}
              className="ds-tab"
              onClick={() => {
                onSelect(board.id)
              }}
            >
              {board.name}
            </button>
          ))}
          <button
            type="button"
            className="ds-tab"
            onClick={() => {
              setDialog({ kind: 'create' })
            }}
          >
            + New board
          </button>
        </div>
        {selected && (
          <span className="flex-none">
            <Menu
              label="Board actions"
              items={[
                {
                  label: 'Add column',
                  onSelect: () => {
                    setDialog({ kind: 'add-column', board: selected })
                  },
                },
                {
                  label: 'Rename',
                  separated: true,
                  onSelect: () => {
                    setDialog({ kind: 'rename', board: selected })
                  },
                },
                {
                  label: 'Duplicate',
                  disabled: clone.isLoading,
                  onSelect: () => {
                    void duplicate()
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
                  disabled: index >= boards.length - 1,
                  onSelect: () => {
                    move(1)
                  },
                },
                {
                  label: 'Delete board',
                  danger: true,
                  separated: true,
                  onSelect: () => {
                    setDialog({ kind: 'delete', board: selected })
                  },
                },
              ]}
            />
          </span>
        )}
      </div>
      {dialog?.kind === 'create' && (
        <BoardForm projectId={projectId} onClose={close} onCreated={onSelect} />
      )}
      {dialog?.kind === 'rename' && (
        <BoardForm projectId={projectId} board={dialog.board} onClose={close} />
      )}
      {dialog?.kind === 'add-column' && (
        <ColumnDialog scope={{ projectId, boardId: dialog.board.id }} onClose={close} />
      )}
      {dialog?.kind === 'delete' && (
        <ConfirmModal
          title={`Delete board "${dialog.board.name}"?`}
          message="Its columns and cards are deleted too. This cannot be undone."
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

function BoardForm({
  projectId,
  board,
  onClose,
  onCreated,
}: {
  projectId: string
  board?: Board
  onClose: () => void
  onCreated?: (boardId: string) => void
}) {
  const [name, setName] = useState(board?.name ?? '')
  const [prefix, setPrefix] = useState(board?.card_prefix ?? '')
  const [createBoard, create] = useCreateBoardMutation()
  const [updateBoard, update] = useUpdateBoardMutation()
  const error = create.error ?? update.error

  const submit = async (event: SyntheticEvent) => {
    event.preventDefault()
    const trimmed = name.trim()
    if (!trimmed) return
    const card_prefix = prefix.trim() || null
    const result = board
      ? await updateBoard({ projectId, boardId: board.id, name: trimmed, card_prefix })
      : await createBoard({ projectId, name: trimmed, card_prefix })
    if (result.data) {
      onClose()
      if (!board) onCreated?.(result.data.id)
    }
  }

  return (
    <Modal title={board ? 'Rename board' : 'New board'} onClose={onClose}>
      <form
        id="board-form"
        onSubmit={(event) => {
          void submit(event)
        }}
      >
        <Input
          name="board-name"
          label="Name"
          value={name}
          required
          maxLength={64}
          onChange={(e) => {
            setName(e.target.value)
          }}
          className="mb2"
        />
        <Input
          name="card-prefix"
          label="Card prefix (optional)"
          placeholder="task"
          value={prefix}
          maxLength={16}
          onChange={(e) => {
            setPrefix(e.target.value)
          }}
          className="mb2"
        />
        {error && <p className="f6 red mt0 mb2">{errorMessage(error)}</p>}
        <div className="flex justify-end" style={{ gap: 8 }}>
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" disabled={create.isLoading || update.isLoading}>
            {board ? 'Save' : 'Create'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}
