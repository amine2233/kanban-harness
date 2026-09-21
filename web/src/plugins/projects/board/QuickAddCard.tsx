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

  if (columns.isLoading) {
    return <Spinner />
  }

  if (columns.error || !columns.data || columns.data.length === 0) {
    onClose()
    return null
  }

  return (
    <CardDialog
      scope={scope}
      columns={columns.data}
      boards={[]}
      columnId={columns.data[0].id}
      onClose={onClose}
    />
  )
}
