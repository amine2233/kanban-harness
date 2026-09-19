import { useState, type SyntheticEvent } from 'react'
import { useAppDispatch, useAppSelector } from '@/app/hooks'
import { Badge, Button, Card, Input, PageHeader, Select } from '@/design-system'
import { addApp, removeApp, selectApps, type AppEntry } from './appsSlice'

export function AppsPage() {
  const apps = useAppSelector(selectApps)
  const dispatch = useAppDispatch()
  const [name, setName] = useState('')
  const [region, setRegion] = useState<AppEntry['region']>('eu')

  const submit = (event: SyntheticEvent) => {
    event.preventDefault()
    const trimmed = name.trim()
    if (!trimmed) return
    dispatch(addApp(trimmed, region))
    setName('')
  }

  return (
    <>
      <PageHeader title="Apps" description="Redux-backed list owned by the apps plugin." />
      <Card title="Create app" className="mb3">
        <form onSubmit={submit} className="flex items-end" style={{ gap: 12 }}>
          <Input
            name="name"
            label="Name"
            value={name}
            maxLength={64}
            onChange={(e) => {
              setName(e.target.value)
            }}
            className="flex-auto"
          />
          <Select
            name="region"
            label="Region"
            value={region}
            onChange={(e) => {
              setRegion(e.target.value as AppEntry['region'])
            }}
          >
            <option value="eu">Europe</option>
            <option value="us">United States</option>
          </Select>
          <Button type="submit">Create</Button>
        </form>
      </Card>
      <Card title={`Apps (${String(apps.length)})`}>
        <ul className="list pl0 ma0">
          {apps.map((app) => (
            <li key={app.id} className="flex items-center justify-between pv2 bb b--light-silver">
              <span className="b near-black">{app.name}</span>
              <span className="flex items-center" style={{ gap: 8 }}>
                <Badge variant="outline">{app.region}</Badge>
                <Button
                  variant="danger"
                  size="sm"
                  onClick={() => {
                    dispatch(removeApp(app.id))
                  }}
                >
                  Remove
                </Button>
              </span>
            </li>
          ))}
        </ul>
      </Card>
    </>
  )
}
