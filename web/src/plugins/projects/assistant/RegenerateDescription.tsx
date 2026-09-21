import { useRef, useState } from 'react'
import { Link } from 'react-router'
import {
  resetDraft,
  streamDraft,
  useAppDispatch,
  useGetAIConfigQuery,
} from '@mvp/state'
import { Button, Icon } from '@mvp/design-system'

interface Props {
  scope: { projectId: string; boardId: string }
  title: string
  currentDescription: string
  onDescription: (description: string) => void
}

/**
 * Button to regenerate description using AI.
 * Takes the current title as context.
 */
export function RegenerateDescription({ scope, title, currentDescription, onDescription }: Props) {
  const { data: ai } = useGetAIConfigQuery()
  const dispatch = useAppDispatch()
  const [loading, setLoading] = useState(false)
  const abort = useRef<() => void>(() => undefined)

  const regenerate = async () => {
    if (!title.trim()) return

    setLoading(true)
    const idea = currentDescription.trim()
      ? `Improve this description for: "${title}". Current description: ${currentDescription}`
      : `Write a detailed description for: "${title}"`

    try {
      const promise = dispatch(streamDraft({ ...scope, idea }))
      abort.current = () => {
        promise.abort()
      }

      const result = await promise.unwrap()
      if (result.draft.description) {
        onDescription(result.draft.description)
      }
    } catch (error) {
      // Handle cancellation or errors silently
    } finally {
      setLoading(false)
      dispatch(resetDraft())
    }
  }

  const providers = ai?.providers ?? []
  const noProvider = ai !== undefined && providers.length === 0

  if (noProvider) {
    return (
      <span className="f6 gray">
        <Link to="/settings">Configure AI</Link> to regenerate
      </span>
    )
  }

  return (
    <Button
      type="button"
      size="sm"
      variant="tertiary"
      disabled={loading || !title.trim()}
      onClick={() => {
        void regenerate()
      }}
      title="Regenerate description with AI"
    >
      {loading ? (
        'Generating...'
      ) : (
        <>
          <Icon name="bolt" size={12} /> Regenerate with AI
        </>
      )}
    </Button>
  )
}
