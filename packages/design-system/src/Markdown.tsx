import { lazy, Suspense } from 'react'
import type { MarkdownProps } from './MarkdownRenderer'

export type { MarkdownProps } from './MarkdownRenderer'

const Renderer = lazy(() => import('./MarkdownRenderer'))

/** Markdown with GFM checklists; the renderer (react-markdown) loads on first use, not with the board. */
export function Markdown(props: MarkdownProps) {
  return (
    <Suspense fallback={<div className="ds-md gray">…</div>}>
      <Renderer {...props} />
    </Suspense>
  )
}
