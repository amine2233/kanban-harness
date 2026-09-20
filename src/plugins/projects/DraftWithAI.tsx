import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router'
import { useAppDispatch, useAppSelector } from '@/app/hooks'
import { Button, Select, Spinner, Textarea } from '@/design-system'
import { useGetAIConfigQuery } from '@/plugins/settings/aiConfigApi'
import { draftPatch, type DraftPatch } from './assistantApi'
import { resetDraft, selectAssistant, streamDraft } from './assistantSlice'

interface Props {
  scope: { projectId: string; boardId: string }
  /** Called with each partial and the final draft; the user still reviews and creates. */
  onDraft: (patch: DraftPatch) => void
}

/** Collapsible "✨ Draft with AI" block for the card dialog, streaming as the model types. */
export function DraftWithAI({ scope, onDraft }: Props) {
  const { data: ai } = useGetAIConfigQuery()
  const dispatch = useAppDispatch()
  const assistant = useAppSelector(selectAssistant)
  const [open, setOpen] = useState(false)
  const [idea, setIdea] = useState('')
  const [provider, setProvider] = useState('')
  const abort = useRef<() => void>(() => undefined)
  const providers = ai?.providers ?? []
  const noProvider = ai !== undefined && providers.length === 0
  const running = assistant.status === 'running'
  const chosen = providers.find((p) => p.id === (provider || ai?.default_provider))
  const [now, setNow] = useState(0)

  useEffect(() => {
    if (assistant.partial) onDraft(draftPatch(assistant.partial))
  }, [assistant.partial, onDraft])
  useEffect(() => {
    if (assistant.result) onDraft(draftPatch(assistant.result.draft))
  }, [assistant.result, onDraft])
  useEffect(
    () => () => {
      abort.current()
      dispatch(resetDraft())
    },
    [dispatch],
  )
  useEffect(() => {
    if (!running) return undefined
    const timer = setInterval(() => {
      setNow(Date.now())
    }, 250)
    return () => {
      clearInterval(timer)
    }
  }, [running])
  const elapsedMs =
    running && assistant.startedAt !== null
      ? Math.max(assistant.elapsedMs, now - assistant.startedAt)
      : assistant.elapsedMs

  const run = () => {
    const trimmed = idea.trim()
    if (!trimmed) return
    const promise = dispatch(
      streamDraft({ ...scope, idea: trimmed, ...(provider ? { provider } : {}) }),
    )
    abort.current = () => {
      promise.abort()
    }
  }

  if (!open) {
    return (
      <Button
        type="button"
        variant="tertiary"
        size="sm"
        className="mb2"
        onClick={() => {
          setOpen(true)
        }}
      >
        ✨ Draft with AI
      </Button>
    )
  }

  return (
    <section className="ds-assist mb3" aria-label="Draft with AI">
      {noProvider ? (
        <p className="f6 gray ma0">
          No AI provider configured yet — add one in{' '}
          <Link to="/settings">Settings → AI providers</Link>.
        </p>
      ) : (
        <>
          <Textarea
            name="ai-idea"
            label="Describe the ticket in a sentence or two"
            placeholder="Users can't reset their password from the mobile app"
            value={idea}
            rows={2}
            disabled={running}
            onChange={(e) => {
              setIdea(e.target.value)
            }}
            className="mb2"
          />
          <div className="flex items-end" style={{ gap: 8 }}>
            {providers.length > 1 && (
              <Select
                name="ai-provider"
                label="Provider"
                value={provider}
                className="flex-auto"
                disabled={running}
                onChange={(e) => {
                  setProvider(e.target.value)
                }}
              >
                <option value="">
                  Default ({providers.find((p) => p.id === ai?.default_provider)?.name ?? '—'})
                </option>
                {providers.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </Select>
            )}
            {running ? (
              <Button
                type="button"
                size="sm"
                variant="secondary"
                onClick={() => {
                  abort.current()
                }}
              >
                Cancel
              </Button>
            ) : (
              <Button type="button" size="sm" disabled={!idea.trim()} onClick={run}>
                Draft
              </Button>
            )}
            <Button
              type="button"
              size="sm"
              variant="tertiary"
              disabled={running}
              onClick={() => {
                setOpen(false)
              }}
            >
              Close
            </Button>
          </div>
          {assistant.status !== 'idle' && (
            <div className="ds-assist__activity mt2" role="status" aria-label="AI activity">
              <div className="flex items-center f6" style={{ gap: 8 }}>
                {running && <Spinner label="Drafting" />}
                <span className="truncate">
                  {[
                    chosen && `${chosen.name} · ${chosen.model}`,
                    assistant.status === 'error' ? 'failed' : assistant.stage,
                    `${String(elapsedMs)} ms`,
                    assistant.usage && tokens(assistant.usage),
                  ]
                    .filter(Boolean)
                    .join(' · ')}
                </span>
              </div>
              {assistant.error && <p className="f6 red mt1 mb0">{assistant.error}</p>}
              {assistant.status === 'done' && (
                <p className="f6 gray mt1 mb0">
                  Drafted by {assistant.result?.provider} ({assistant.result?.model}) — review
                  below, then Create.
                </p>
              )}
              {assistant.log.length > 0 && (
                <details className="f6 gray mt1">
                  <summary>Log ({String(assistant.log.length)})</summary>
                  <ol className="ds-assist__log">
                    {assistant.log.map((entry, i) => (
                      <li key={i}>
                        <code>{String(entry.elapsed_ms)} ms</code> {entry.name}
                      </li>
                    ))}
                  </ol>
                </details>
              )}
            </div>
          )}
        </>
      )}
    </section>
  )
}

function tokens(usage: {
  input_tokens: number | null
  output_tokens: number | null
  cost_usd: number | null
}) {
  const parts = [
    usage.input_tokens !== null && `${String(usage.input_tokens)} in`,
    usage.output_tokens !== null && `${String(usage.output_tokens)} out`,
    usage.cost_usd !== null && `$${usage.cost_usd.toFixed(4)}`,
  ].filter(Boolean)
  return parts.length > 0 ? parts.join(' / ') : null
}
