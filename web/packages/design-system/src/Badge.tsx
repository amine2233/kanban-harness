import type { HTMLAttributes } from 'react'
import { cx } from './cx'

export type BadgeVariant = 'default' | 'square' | 'outline' | 'alpha' | 'beta' | 'new' | 'code'

export interface BadgeProps extends HTMLAttributes<HTMLSpanElement> {
  variant?: BadgeVariant
}

export function Badge({ variant = 'default', className, ...rest }: BadgeProps) {
  const cls = variant === 'default' ? 'hk-badge' : `hk-badge--${variant}`
  return <span className={cx(cls, className)} {...rest} />
}
