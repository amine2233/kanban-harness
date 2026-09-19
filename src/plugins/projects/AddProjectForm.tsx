import { useState, type SyntheticEvent } from 'react'
import { useNavigate } from 'react-router'
import { errorMessage } from '@/app/api'
import { Button, Input, Select } from '@/design-system'
import { folderName } from './paths'
import { useCreateProjectMutation, type StorageKind } from './projectsApi'

export function AddProjectForm({ onDone }: { onDone: () => void }) {
  const navigate = useNavigate()
  const [createProject, { isLoading, error }] = useCreateProjectMutation()
  const [name, setName] = useState('')
  const [path, setPath] = useState('')
  const [storage, setStorage] = useState<StorageKind>('json')

  const submit = async (event: SyntheticEvent) => {
    event.preventDefault()
    const trimmedPath = path.trim()
    if (!trimmedPath) return
    const result = await createProject({
      name: name.trim() || folderName(trimmedPath),
      path: trimmedPath,
      storage,
    })
    if (result.data) {
      onDone()
      await navigate(`/projects/${result.data.id}`)
    }
  }

  return (
    <form
      onSubmit={(event) => {
        void submit(event)
      }}
      className="pa2 mb2 bg-lightest-silver br2"
      aria-label="Add project"
    >
      <Input
        name="path"
        label="Folder path"
        placeholder="/Users/me/projects/demo"
        value={path}
        required
        onChange={(e) => {
          setPath(e.target.value)
        }}
        className="mb2"
      />
      <Input
        name="name"
        label="Name (optional)"
        value={name}
        maxLength={64}
        onChange={(e) => {
          setName(e.target.value)
        }}
        className="mb2"
      />
      <Select
        name="storage"
        label="Storage"
        value={storage}
        onChange={(e) => {
          setStorage(e.target.value as StorageKind)
        }}
        className="mb2"
      >
        <option value="json">JSON (kanban.json)</option>
        <option value="sqlite">SQLite (kanban.sqlite)</option>
      </Select>
      {error && <p className="f6 red mt0 mb2">{errorMessage(error)}</p>}
      <div className="flex" style={{ gap: 8 }}>
        <Button type="submit" size="sm" disabled={isLoading}>
          Add
        </Button>
        <Button type="button" size="sm" variant="secondary" onClick={onDone}>
          Cancel
        </Button>
      </div>
    </form>
  )
}
