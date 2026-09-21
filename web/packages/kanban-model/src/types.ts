/** Wire types of the kanban API (snake_case, explicit nulls), shared by every front-end module. */

export interface Page<T> {
  items: T[]
  total: number
  page: number
  page_size: number
  total_pages: number
}

export interface Board {
  id: string
  name: string
  description: string | null
  card_prefix: string | null
  position: number
}

export interface Column {
  id: string
  board_id: string
  name: string
  position: number
  wip_limit: number | null
  default_status: CardStatus | null
}

export type CardPriority = 'low' | 'medium' | 'high' | 'critical'
export type CardStatus = 'todo' | 'in_progress' | 'blocked' | 'done'

export interface Card {
  id: string
  column_id: string
  board_id: string
  prefix: string
  card_number: number
  title: string
  description: string | null
  priority: CardPriority
  status: CardStatus
  position: number
  due_date: string | null
  points: number | null
  ai_cost: AICost | null
  /** Set when the card is a sub-task of another card on the board. */
  parent_id: string | null
  children: { total: number; done: number }
}

export interface NewSubtask {
  title: string
  description?: string | null
  priority?: CardPriority
  points?: number | null
}

/** What drafting the card with AI cost; absent on hand-written cards. */
export interface AICost {
  provider: string
  model: string
  input_tokens: number | null
  output_tokens: number | null
  cost_usd: number | null
  estimated: boolean
}

/** PATCH body for a card; `null` clears a field, `board_id` moves it to another board. */
export interface CardPatch {
  title?: string
  description?: string | null
  priority?: CardPriority
  status?: CardStatus
  column_id?: string
  board_id?: string
  due_date?: string | null
  points?: number | null
}
