import { useState } from 'react'
import { Link } from 'react-router'
import { errorMessage } from '@/app/api'
import { Button, Select, Spinner, Textarea } from '@/design-system'
import { useGetAIConfigQuery } from '@/plugins/settings/aiConfigApi'
import { draftDescription, useDraftTicketMutation, type TicketDraft } from './assistantApi'

interface Props {
  scope: { projectId: string; boardId: string }
  /** Receives the draft to pre-fill the card form; the user still reviews and creates. */
  onDraft: (draft: TicketDraft, description: string) => void
}

/** Collapsible "✨ Draft with AI" block for the card dialog. */
export function DraftWithAI({ scope, onDraft }: Props) {
  const { data: ai } = useGetAIConfigQuery()
  const [open, setOpen] = useState(false)
  const [idea, setIdea] = useState('')
  const [provider, setProvider] = useState('')
  const [draft, result] = useDraftTicketMutation()
  const providers = ai?.providers ?? []
  const noProvider = ai !== undefined && providers.length === 0

  const run = async () => {
    const trimmed = idea.trim()
    if (!trimmed) return
    const outcome = await draft({ ...scope, idea: trimmed, ...(provider ? { provider } : {}) })
    if (outcome.data) onDraft(outcome.data.draft, draftDescription(outcome.data.draft))
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
            <Button
              type="button"
              size="sm"
              disabled={result.isLoading || !idea.trim()}
              onClick={() => {
                void run()
              }}
            >
              {result.isLoading ? <Spinner inverted label="Drafting" /> : 'Draft'}
            </Button>
            <Button
              type="button"
              size="sm"
              variant="tertiary"
              onClick={() => {
                setOpen(false)
              }}
            >
              Close
            </Button>
          </div>
          {result.error && <p className="f6 red mt2 mb0">{errorMessage(result.error)}</p>}
          {result.data && (
            <p className="f6 gray mt2 mb0">
              Drafted by {result.data.provider} ({result.data.model}) — review below, then Create.
            </p>
          )}
        </>
      )}
    </section>
  )
}
