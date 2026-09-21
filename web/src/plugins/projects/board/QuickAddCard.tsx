import { useEffect } from 'react'
import { CardDialog } from '../card/CardDialog'
import { useListColumnsQuery } from '@mvp/state'
import { Spinner } from '@mvp/design-system'

interface Props {
  scope: { projectId: string; boardId: string }
  onClose: () => void
}

/**
 * Quick card creation from floating action button.
 * Loads columns and opens CardDialog with first column selected.
 */
export function QuickAddCard({ scope, onClose }: Props) {
  const columns = useListColumnsQuery(scope)
  const first = columns.data?.[0]
  const unusable = !columns.isLoading && first === undefined

  useEffect(() => {
    if (unusable) onClose()
  }, [unusable, onClose])

  if (columns.isLoading) {
    return <Spinner />
  }
  if (!columns.data || first === undefined) {
    return null
  }

  return (
    <CardDialog
      scope={scope}
      columns={columns.data}
      boards={[]}
      columnId={first.id}
      onClose={onClose}
    />
  )
}
