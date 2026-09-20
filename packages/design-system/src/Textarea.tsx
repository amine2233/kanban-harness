import type { TextareaHTMLAttributes } from 'react'
import { cx } from './cx'

export interface TextareaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: string
}

export function Textarea({ label, id, className, ...rest }: TextareaProps) {
  const textareaId = id ?? rest.name
  return (
    <div className={className}>
      {label && (
        <label htmlFor={textareaId} className="hk-label db">
          {label}
        </label>
      )}
      <textarea id={textareaId} className={cx('hk-input', 'w-100')} rows={4} {...rest} />
    </div>
  )
}
