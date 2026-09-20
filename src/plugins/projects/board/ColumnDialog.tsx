import { useState, type SyntheticEvent } from 'react'
import { errorMessage } from '@/app/api'
import { Button, Input, Modal, Row, Select } from '@mvp/design-system'
import {
  useCreateColumnMutation,
  useUpdateColumnMutation,
  type CardStatus,
  type Column,
} from '../api/kanbanApi'

const STATUSES: CardStatus[] = ['todo', 'in_progress', 'blocked', 'done']

interface Props {
  scope: { projectId: string; boardId: string }
  column?: Column | undefined
  onClose: () => void
}

export function ColumnDialog({ scope, column, onClose }: Props) {
  const [name, setName] = useState(column?.name ?? '')
  const [wip, setWip] = useState(
    column?.wip_limit === null || column === undefined ? '' : String(column.wip_limit),
  )
  const [status, setStatus] = useState<CardStatus | ''>(column?.default_status ?? '')
  const [createColumn, create] = useCreateColumnMutation()
  const [updateColumn, update] = useUpdateColumnMutation()
  const error = create.error ?? update.error

  const submit = async (event: SyntheticEvent) => {
    event.preventDefault()
    const trimmed = name.trim()
    if (!trimmed) return
    const fields = {
      name: trimmed,
      wip_limit: wip === '' ? null : Number(wip),
      default_status: status === '' ? null : status,
    }
    const result = column
      ? await updateColumn({ ...scope, columnId: column.id, ...fields })
      : await createColumn({ ...scope, ...fields })
    if (result.data) onClose()
  }

  return (
    <Modal title={column ? 'Edit column' : 'New column'} onClose={onClose}>
      <form
        onSubmit={(event) => {
          void submit(event)
        }}
      >
        <Input
          name="column-name"
          label="Name"
          value={name}
          required
          maxLength={64}
          onChange={(e) => {
            setName(e.target.value)
          }}
          className="mb2"
        />
        <Row className="mb2">
          <Input
            name="column-wip"
            label="WIP limit"
            type="number"
            min={0}
            value={wip}
            className="flex-auto"
            onChange={(e) => {
              setWip(e.target.value)
            }}
          />
          <Select
            name="column-status"
            label="Default status"
            value={status}
            className="flex-auto"
            onChange={(e) => {
              setStatus(e.target.value as CardStatus | '')
            }}
          >
            <option value="">none</option>
            {STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </Select>
        </Row>
        {error && <p className="f6 red mt0 mb2">{errorMessage(error)}</p>}
        <Row className="justify-end">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" disabled={create.isLoading || update.isLoading}>
            {column ? 'Save' : 'Create'}
          </Button>
        </Row>
      </form>
    </Modal>
  )
}
