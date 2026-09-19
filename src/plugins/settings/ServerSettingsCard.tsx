import { useState, type SyntheticEvent } from 'react'
import { errorMessage } from '@/app/api'
import { Banner, Button, Card, Select, Spinner, Textarea } from '@/design-system'
import type { StorageKind } from '@/plugins/projects/projectsApi'
import { splitOrigins } from './origins'
import {
  useGetServerSettingsQuery,
  useUpdateServerSettingsMutation,
  type ServerSettings,
} from './settingsApi'

/** Edits settings.json on the server; the server applies them without a restart. */
export function ServerSettingsCard() {
  const { data, isLoading, error } = useGetServerSettingsQuery()
  const [update, result] = useUpdateServerSettingsMutation()
  return (
    <Card title="Server" className="mw7 mt3">
      {isLoading && <Spinner />}
      {error && (
        <Banner tone="danger" title="Cannot load server settings">
          {errorMessage(error)}
        </Banner>
      )}
      {data && (
        <ServerSettingsForm
          key={JSON.stringify(data)}
          settings={data}
          saving={result.isLoading}
          saveError={result.error}
          saved={result.isSuccess}
          onSave={(patch) => {
            void update(patch)
          }}
        />
      )}
    </Card>
  )
}

interface FormProps {
  settings: ServerSettings
  saving: boolean
  saveError: unknown
  saved: boolean
  onSave: (patch: Partial<ServerSettings>) => void
}

function ServerSettingsForm({ settings, saving, saveError, saved, onSave }: FormProps) {
  const [storage, setStorage] = useState<StorageKind>(settings.default_storage)
  const [origins, setOrigins] = useState(settings.cors_origins.join('\n'))
  const dirty =
    storage !== settings.default_storage ||
    splitOrigins(origins).join() !== settings.cors_origins.join()

  const save = (event: SyntheticEvent) => {
    event.preventDefault()
    onSave({ default_storage: storage, cors_origins: splitOrigins(origins) })
  }

  return (
    <form onSubmit={save}>
      <p className="f6 gray mt0 mb3">
        Stored in <code>settings.json</code> on the server and applied immediately — no restart.
      </p>
      <Select
        name="default-storage"
        label="Default storage for new projects"
        value={storage}
        className="mb2 mw5"
        onChange={(e) => {
          setStorage(e.target.value as StorageKind)
        }}
      >
        <option value="json">JSON (kanban.json)</option>
        <option value="sqlite">SQLite (kanban.sqlite)</option>
      </Select>
      <Textarea
        name="cors-origins"
        label="Allowed browser origins (CORS), one per line"
        placeholder="http://localhost:5173"
        value={origins}
        rows={3}
        onChange={(e) => {
          setOrigins(e.target.value)
        }}
        className="mb1"
      />
      <p className="f6 gray mt0 mb3">
        Needed only when this dashboard is served from a different origin than the API.
      </p>
      {saveError !== undefined && <p className="f6 red mt0 mb2">{errorMessage(saveError)}</p>}
      {saved && !dirty && <p className="f6 green mt0 mb2">Saved and applied.</p>}
      <Button type="submit" disabled={!dirty || saving}>
        Save server settings
      </Button>
    </form>
  )
}
