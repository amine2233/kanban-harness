import type { ReactNode } from 'react'
import { cx } from './cx'

export type Tone = 'generic' | 'info' | 'success' | 'warning' | 'danger'

export interface BannerProps {
  tone?: Tone
  title: string
  children?: ReactNode
  className?: string
}

export function Banner({ tone = 'generic', title, children, className }: BannerProps) {
  return (
    <div role="status" className={cx(`hk-banner--${tone}`, 'flex', className)}>
      <div className="flex-auto">
        <div className="b">{title}</div>
        {children && <div>{children}</div>}
      </div>
    </div>
  )
}
