import type { ElementType, HTMLAttributes, ReactNode } from 'react'
import { cx } from './cx'

type Gap = 'xs' | 'sm' | 'md'

interface LayoutProps extends HTMLAttributes<HTMLElement> {
  /** Element to render; `div` by default, `li` inside lists. */
  as?: ElementType
  gap?: Gap
  /** Cross-axis alignment; rows centre by default, stacks stretch. */
  align?: 'start' | 'center' | 'end' | 'stretch'
  children?: ReactNode
}

/** Horizontal flex line with a consistent gap. Replaces `className="flex" style={{ gap }}`. */
export function Row({
  as: Tag = 'div',
  gap = 'sm',
  align = 'center',
  className,
  ...rest
}: LayoutProps) {
  return <Tag className={cx('ds-row', `ds-gap-${gap}`, `ds-align-${align}`, className)} {...rest} />
}

/** Vertical flex column with a consistent gap. */
export function Stack({
  as: Tag = 'div',
  gap = 'sm',
  align = 'stretch',
  className,
  ...rest
}: LayoutProps) {
  return (
    <Tag className={cx('ds-stack', `ds-gap-${gap}`, `ds-align-${align}`, className)} {...rest} />
  )
}
