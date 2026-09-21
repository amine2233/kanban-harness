import { useEffect, type ReactNode } from 'react'
import { Button } from './Button'

export interface ModalProps {
  title: string
  onClose: () => void
  children: ReactNode
  footer?: ReactNode
}

/** Overlay dialog; Escape closes it. Mount it only while open. */
export function Modal({ title, onClose, children, footer }: ModalProps) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('keydown', onKey)
    }
  }, [onClose])

  return (
    <div className="ds-modal-backdrop" onClick={onClose}>
      <div
        className="ds-modal bg-white br2 shadow-outer-1"
        role="dialog"
        aria-modal="true"
        aria-labelledby="ds-modal-title"
        onClick={(event) => {
          event.stopPropagation()
        }}
      >
        <header className="flex items-center justify-between ph3 pv2 bb b--light-silver">
          <h2 id="ds-modal-title" className="f3 b dark-gray ma0">
            {title}
          </h2>
          <Button variant="tertiary" size="sm" aria-label="Close" onClick={onClose}>
            ×
          </Button>
        </header>
        <div className="pa3">{children}</div>
        {footer && (
          <footer className="flex justify-end ph3 pv2 bt b--light-silver ds-modal-footer">
            {footer}
          </footer>
        )}
      </div>
    </div>
  )
}

export interface ConfirmModalProps {
  title: string
  message: string
  confirmLabel?: string
  busy?: boolean
  onConfirm: () => void
  onClose: () => void
  children?: ReactNode
}

export function ConfirmModal({
  title,
  message,
  confirmLabel = 'Delete',
  busy = false,
  onConfirm,
  onClose,
  children,
}: ConfirmModalProps) {
  return (
    <Modal
      title={title}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="danger-primary" disabled={busy} onClick={onConfirm}>
            {confirmLabel}
          </Button>
        </>
      }
    >
      <p className="ma0">{message}</p>
      {children}
    </Modal>
  )
}
