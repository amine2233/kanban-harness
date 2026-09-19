import type { SelectHTMLAttributes } from 'react'
import { cx } from './cx'

export interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  label?: string
}

export function Select({ label, id, disabled, className, ...rest }: SelectProps) {
  const selectId = id ?? rest.name
  return (
    <div className={className}>
      {label && (
        <label htmlFor={selectId} className="hk-label db">
          {label}
        </label>
      )}
      <select
        id={selectId}
        className={cx(disabled ? 'hk-select--disabled' : 'hk-select', 'w-100')}
        disabled={disabled}
        {...rest}
      />
    </div>
  )
}
