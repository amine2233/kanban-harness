import { isValidElement, type ReactNode } from 'react'
import ReactMarkdown, { type Components } from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { cx } from './cx'
import { toggleTask } from './markdownTasks'

export interface MarkdownProps {
  source: string
  className?: string
  /** When given, task-list checkboxes become clickable and hand back the updated source. */
  onChange?: (source: string) => void
}

/** Renders GitHub-flavoured markdown (checklists, tables, strikethrough); links open in a new tab. */
export default function MarkdownRenderer({ source, className, onChange }: MarkdownProps) {
  const components: Components = {
    a: ({ href, children }) => (
      <a href={href} target="_blank" rel="noreferrer">
        {children}
      </a>
    ),
    li: ({ node, className: liClass, children, ...props }) => {
      const line = node?.position?.start.line
      const task = /\btask-list-item\b/.test(liClass ?? '')
      if (!task || line === undefined) {
        return (
          <li className={liClass} {...props}>
            {children}
          </li>
        )
      }
      const checked = /^\s*[-*+]\s+\[[xX]\]/.test(source.split('\n')[line - 1] ?? '')
      return (
        <li className={cx(liClass, 'ds-md__task', checked && 'ds-md__task--done')}>
          <label>
            <input
              type="checkbox"
              checked={checked}
              disabled={!onChange}
              onChange={() => {
                onChange?.(toggleTask(source, line))
              }}
            />{' '}
            <span>{stripCheckbox(children)}</span>
          </label>
        </li>
      )
    },
  }
  return (
    <div className={cx('ds-md', className)}>
      <ReactMarkdown remarkPlugins={[remarkGfm]} components={components}>
        {source}
      </ReactMarkdown>
    </div>
  )
}

/** react-markdown renders the task checkbox itself as the first child; we draw our own. */
function stripCheckbox(children: ReactNode): ReactNode {
  if (!Array.isArray(children)) return children
  return (children as ReactNode[]).filter(
    (child) => !isValidElement(child) || child.type !== 'input',
  )
}
