import { useState, type SyntheticEvent } from 'react'
import { ThemePicker } from '@/core/settings/ThemePicker'
import { AIProvidersCard } from './AIProvidersCard'
import { ServerSettingsCard } from './ServerSettingsCard'
import {
  apiBaseUrl,
  baseApi,
  normaliseServerUrl,
  resetSettings,
  selectServerUrl,
  setServerUrl,
  useAppDispatch,
  useAppSelector,
} from '@mvp/state'
import { Banner, Button, Card, Input, PageHeader, Row, type Tone } from '@mvp/design-system'

interface Check {
  tone: Tone
  title: string
  detail?: string
}

export function SettingsPage() {
  const dispatch = useAppDispatch()
  const serverUrl = useAppSelector(selectServerUrl)
  const [draft, setDraft] = useState(serverUrl)
  const [check, setCheck] = useState<Check>()
  const [checking, setChecking] = useState(false)
  const normalised = normaliseServerUrl(draft)
  const invalid = normalised === null

  const apply = (url: string) => {
    dispatch(url === '' ? resetSettings() : setServerUrl(url))
    dispatch(baseApi.util.resetApiState())
    setDraft(url)
    setCheck({
      tone: 'success',
      title: 'Saved',
      detail: `API requests now go to ${apiBaseUrl(url)}`,
    })
  }

  const save = (event: SyntheticEvent) => {
    event.preventDefault()
    if (normalised === null) return
    apply(normalised)
  }

  const test = async () => {
    if (normalised === null) return
    setChecking(true)
    try {
      const response = await fetch(`${apiBaseUrl(normalised)}/health`)
      setCheck(
        response.ok
          ? { tone: 'success', title: 'Server reachable', detail: apiBaseUrl(normalised) }
          : { tone: 'danger', title: `Server answered ${String(response.status)}` },
      )
    } catch (error) {
      setCheck({ tone: 'danger', title: 'Server unreachable', detail: String(error) })
    } finally {
      setChecking(false)
    }
  }

  return (
    <>
      <PageHeader title="Settings" description="This browser, and the server it talks to." />
      <Card title="This browser" className="mw7">
        <form onSubmit={save}>
          <Input
            name="server-url"
            label="Server URL"
            placeholder={`Same origin (${window.location.origin})`}
            value={draft}
            onChange={(e) => {
              setDraft(e.target.value)
            }}
            className="mb1"
          />
          <p className="f6 gray mt0 mb3">
            Stored in this browser only. Leave empty to use the page&apos;s own origin. Currently
            using <code>{apiBaseUrl(serverUrl)}</code>.
          </p>
          {invalid && (
            <p className="f6 red mt0 mb2">Enter an absolute http(s) URL, or leave it empty.</p>
          )}
          <Row>
            <Button type="submit" disabled={invalid || normalised === serverUrl}>
              Save
            </Button>
            <Button
              type="button"
              variant="secondary"
              disabled={invalid || checking}
              onClick={() => {
                void test()
              }}
            >
              Test connection
            </Button>
            <Button
              type="button"
              variant="tertiary"
              disabled={serverUrl === '' && draft === ''}
              onClick={() => {
                apply('')
              }}
            >
              Reset to default
            </Button>
          </Row>
        </form>
        {check && (
          <Banner tone={check.tone} title={check.title} className="mt3">
            {check.detail}
          </Banner>
        )}
      </Card>
      <Card title="Appearance" className="mw7 mt3">
        <p className="f6 gray mt0 mb2">
          <em>System</em> follows your OS setting and switches automatically; pick Light or Dark to
          force one. Stored in this browser.
        </p>
        <ThemePicker />
      </Card>
      <ServerSettingsCard />
      <AIProvidersCard />
    </>
  )
}
