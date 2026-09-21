export const CARD_MIME = 'application/x-dashboard-card'

export function serialiseCardDrag(cardId: string, columnId: string): string {
  return `${cardId}|${columnId}`
}

/** Reads the dragged card from a drop event; null when the drag is not a card. */
export function draggedCard(
  dataTransfer: DataTransfer,
): { cardId: string; columnId: string } | null {
  const raw = dataTransfer.getData(CARD_MIME)
  if (!raw) return null
  const [cardId, columnId] = raw.split('|')
  return cardId && columnId ? { cardId, columnId } : null
}
