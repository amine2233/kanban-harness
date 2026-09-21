import { useId, useState } from 'react'
import { Markdown } from '@mvp/design-system'

interface Props {
  value: string
  onChange: (value: string) => void
  /** Called when a checklist item is ticked in the preview (e.g. to save straight away). */
  onToggle?: ((value: string) => void) | undefined
  /** Open on the preview when there is something to read. */
  initialMode?: 'write' | 'preview'
}

/** Markdown description with Write / Preview tabs; checklists are clickable in the preview. */
export function DescriptionField({ value, onChange, onToggle, initialMode }: Props) {
  const [mode, setMode] = useState<'write' | 'preview'>(
    initialMode ?? (value.trim() ? 'preview' : 'write'),
  )
  const id = useId()
  return (
    <div className="mb2">
      <label className="hk-label" htmlFor={`${id}-text`}>
        Description
      </label>
      <div className="ds-desc">
        <div className="ds-desc__tabs" role="tablist" aria-label="Description mode">
          {(['write', 'preview'] as const).map((tab) => (
            <button
              key={tab}
              type="button"
              role="tab"
              className="ds-desc__tab"
              aria-selected={mode === tab}
              onClick={() => {
                setMode(tab)
              }}
            >
              {tab === 'write' ? 'Write' : 'Preview'}
            </button>
          ))}
          <span className="flex-auto tr f7 gray pt1 pr1">markdown · `- [ ]` makes a checklist</span>
        </div>
        {mode === 'write' ? (
          <textarea
            id={`${id}-text`}
            name="card-description"
            className="hk-input w-100"
            rows={6}
            value={value}
            onChange={(e) => {
              onChange(e.target.value)
            }}
          />
        ) : (
          <div className="ds-desc__preview" role="tabpanel" aria-label="Description preview">
            {value.trim() ? (
              <Markdown
                source={value}
                onChange={(next) => {
                  onChange(next)
                  onToggle?.(next)
                }}
              />
            ) : (
              <span className="ds-desc__preview--empty">Nothing written yet.</span>
            )}
            <input id={`${id}-text`} type="hidden" value={value} readOnly />
          </div>
        )}
      </div>
    </div>
  )
}
