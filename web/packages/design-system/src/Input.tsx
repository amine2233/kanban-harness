import type { InputHTMLAttributes } from 'react'
import { cx } from './cx'

export interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string
}

export function Input({ label, id, disabled, readOnly, className, ...rest }: InputProps) {
  const inputId = id ?? rest.name
  const cls = disabled ? 'hk-input--disabled' : readOnly ? 'hk-input--read-only' : 'hk-input'
  return (
    <div className={className}>
      {label && (
        <label htmlFor={inputId} className="hk-label db">
          {label}
        </label>
      )}
      <input
        id={inputId}
        className={cx(cls, 'w-100')}
        disabled={disabled}
        readOnly={readOnly}
        {...rest}
      />
    </div>
  )
}
