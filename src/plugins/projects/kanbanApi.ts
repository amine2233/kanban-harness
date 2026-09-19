import { baseApi } from '@/app/api'

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
}

export interface Column {
  id: string
  board_id: string
  name: string
  position: number
  wip_limit: number | null
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
}

interface BoardScope {
  projectId: string
  boardId: string
}

const PAGE_SIZE = 500

/** kanban-server's REST API, proxied per project by dashboard-server. */
export const kanban = (projectId: string) => `projects/${projectId}/kanban/v1`

export const kanbanApi = baseApi.injectEndpoints({
  endpoints: (build) => ({
    listBoards: build.query<Board[], string>({
      query: (projectId) => `${kanban(projectId)}/boards?page_size=${String(PAGE_SIZE)}`,
      transformResponse: (page: Page<Board>) => page.items,
      providesTags: (_result, _error, projectId) => [{ type: 'Board', id: projectId }],
    }),
    listColumns: build.query<Column[], BoardScope>({
      query: ({ projectId, boardId }) =>
        `${kanban(projectId)}/boards/${boardId}/columns?page_size=${String(PAGE_SIZE)}`,
      transformResponse: (page: Page<Column>) =>
        [...page.items].sort((a, b) => a.position - b.position),
      providesTags: (_result, _error, { boardId }) => [{ type: 'Column', id: boardId }],
    }),
    listCards: build.query<Card[], BoardScope>({
      query: ({ projectId, boardId }) =>
        `${kanban(projectId)}/boards/${boardId}/cards?page_size=${String(PAGE_SIZE)}`,
      transformResponse: (page: Page<Card>) => page.items,
      providesTags: (_result, _error, { boardId }) => [{ type: 'Card', id: boardId }],
    }),
    createCard: build.mutation<
      Card,
      BoardScope & { columnId: string; title: string; priority: CardPriority }
    >({
      query: ({ projectId, columnId, title, priority }) => ({
        url: `${kanban(projectId)}/columns/${columnId}/cards`,
        method: 'POST',
        body: { title, priority },
      }),
      invalidatesTags: (_result, _error, { boardId }) => [{ type: 'Card', id: boardId }],
    }),
    moveCard: build.mutation<Card, BoardScope & { cardId: string; columnId: string }>({
      query: ({ projectId, boardId, cardId, columnId }) => ({
        url: `${kanban(projectId)}/boards/${boardId}/cards/${cardId}`,
        method: 'PATCH',
        body: { column_id: columnId },
      }),
      invalidatesTags: (_result, _error, { boardId }) => [{ type: 'Card', id: boardId }],
    }),
    // eslint-disable-next-line @typescript-eslint/no-invalid-void-type -- 204 has no body
    deleteCard: build.mutation<void, BoardScope & { cardId: string }>({
      query: ({ projectId, boardId, cardId }) => ({
        url: `${kanban(projectId)}/boards/${boardId}/cards/${cardId}`,
        method: 'DELETE',
      }),
      invalidatesTags: (_result, _error, { boardId }) => [{ type: 'Card', id: boardId }],
    }),
  }),
})

export const {
  useListBoardsQuery,
  useListColumnsQuery,
  useListCardsQuery,
  useCreateCardMutation,
  useMoveCardMutation,
  useDeleteCardMutation,
} = kanbanApi
