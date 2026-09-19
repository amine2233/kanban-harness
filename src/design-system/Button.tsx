import type { ButtonHTMLAttributes } from 'react'
import { cx } from './cx'

export type ButtonVariant =
  | 'primary'
  | 'secondary'
  | 'tertiary'
  | 'danger'
  | 'danger-primary'
  | 'warning'
  | 'info'
  | 'success'

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant
  size?: 'md' | 'sm'
}

export function Button({
  variant = 'primary',
  size = 'md',
  type = 'button',
  className,
  ...rest
}: ButtonProps) {
  const base = size === 'sm' ? 'hk-button-sm' : 'hk-button'
  return <button type={type} className={cx(`${base}--${variant}`, className)} {...rest} />
}
