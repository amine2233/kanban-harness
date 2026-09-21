---
title: Architecture
---

# Web app — architecture

The web application is a React 19 + TypeScript frontend using Redux Toolkit for state management and RTK Query for API communication with the Swift Vapor backend.

## Package Structure

The web app is a pnpm workspace: three library packages and one application. Dependencies only point downwards; a package never imports from the one above it.

```text
web/src/                the app: shell, router, plugins (components only)
  │
  ├── @mvp/state        web/packages/state    Redux store, API endpoints, live socket, AI stream
  │      │
  │      └── @mvp/kanban-model   web/packages/kanban-model   wire types + pure functions over the board
  │
  └── @mvp/design-system   web/packages/design-system   UI components over purple3, no state
```

| Package              | Depends on          | Knows about                                   | Never contains                 |
| -------------------- | ------------------- | --------------------------------------------- | ------------------------------ |
| `@mvp/kanban-model`  | nothing             | `Card`, `Column`, drafts, colours, checklists | React, Redux, `fetch`          |
| `@mvp/design-system` | React               | `hk-*`/`ds-*` classes, markdown, icons        | the store, the API, the domain |
| `@mvp/state`         | kanban-model, Redux | the API, settings, the socket, the AI stream  | components, JSX                |
| `src/` (app)         | all three           | pages, dialogs, the board, the shell          | `fetch`, hand-written CSS      |

The layering is **enforced by ESLint** (`no-restricted-imports` blocks in `eslint.config.js`): `kanban-model` cannot import React or Redux, `design-system` cannot import the store or the domain, `state` cannot import React components, and the app must import packages by name, never by path.

---

## Database Architecture

### Backend Storage Model

The dashboard uses **SQLite** databases with two distinct levels:

#### 1. Registry Database (Server-Level)
- **Location**: `~/.mvp-dashboard/projects.sqlite` (configurable via `home` setting)
- **Purpose**: Stores the **project registry** (list of all projects, metadata, paths, settings)
- **Lifetime**: Single database for the entire server instance
- **Schema**: Project metadata (id, name, path, storage type)
- **Access**: Server-wide, shared across all requests

#### 2. Workspace Databases (Per-Project)
- **Location**: One `.sqlite` file **per project** (inside each project folder: `<project-path>/kanban.sqlite`)
- **Purpose**: Stores **kanban workspace data** for that specific project:
  - Boards
  - Columns
  - Cards
  - Sections
  - Card prefixes
- **Lifetime**: Created lazily on first access, kept in connection pool
- **Schema**: Full kanban model (boards, columns, cards with relationships)
- **Access**: Per-project isolation via `SQLiteDatabasePool`

### Configuration Scope

Database configuration (thread pool size, connection settings) is **server-wide** and applies to both registry and all workspace databases.

Configuration file: `~/.mvp-dashboard/config.yaml`
```yaml
database:
  thread_pool_size: 2  # Threads per SQLite connection
```

Environment variable override: `MVP_DASHBOARD_DATABASE_THREAD_POOL_SIZE=4`

---

## State Management

### Redux Store Structure

```
web/packages/state/src/
├── api/
│   ├── baseApi.ts          # RTK Query base API with tags
│   ├── projectsApi.ts      # Project CRUD operations
│   ├── kanbanApi.ts        # Boards, columns, cards operations
│   └── aiApi.ts            # AI provider configuration
├── live/                   # WebSocket connection
└── assistant/              # AI drafting state
```

### RTK Query Cache Invalidation

The application uses **tag-based cache invalidation**:

- **`Board` tag** (scoped by `projectId`):
  - Invalidated when: boards created/updated/deleted/cloned
  - Refetches: board list for that project

- **`Column` tag** (scoped by `boardId`):
  - Invalidated when: columns created/updated/deleted
  - Refetches: column list for that board

- **`Card` tag** (scoped by `boardId`):
  - Invalidated when: cards created/moved/updated/deleted
  - Refetches: card list for that board

### Project Switching

When switching projects in the sidebar:

1. **Route changes**: `/projects/:projectId`
2. **Component remounts**: `<KanbanBoard key={projectId}>` forces fresh mount
3. **Query parameters update**: RTK Query sees new `projectId`
4. **Cache lookup**: Checks cache for this project's data
5. **Fetch if needed**: Loads data from backend if not cached

**Cache key structure**:
- Boards: `["listBoards", projectId]`
- Columns: `["listColumns", { projectId, boardId }]`
- Cards: `["listCards", { projectId, boardId }]`

Different `projectId` values = different cache entries = no stale data issues.

---

## API Communication

### Base URL

- Development: `http://localhost:5175/api` (proxied by Vite)
- Production: `/api` (served by same backend)

### Request Flow

```
Frontend Component
    ↓ (uses RTK Query hook)
Redux RTK Query
    ↓ (HTTP request)
Vapor Backend (Swift)
    ↓ (via ProjectService actor)
SQLiteDatabasePool
    ↓ (lazy connection)
Workspace SQLite Database
    ↓ (Fluent ORM)
SQLite File on Disk
```

### Main API Endpoints

#### Projects
```
GET    /api/projects              # List all projects
POST   /api/projects              # Register new project
GET    /api/projects/:id          # Get project details
PATCH  /api/projects/:id          # Update project (name, storage)
DELETE /api/projects/:id          # Unregister project
```

#### Kanban (per-project)
```
GET    /api/projects/:projectId/kanban/v1/boards
POST   /api/projects/:projectId/kanban/v1/boards
PATCH  /api/projects/:projectId/kanban/v1/boards/:boardId
DELETE /api/projects/:projectId/kanban/v1/boards/:boardId
POST   /api/projects/:projectId/kanban/v1/boards/:boardId/clone

GET    /api/projects/:projectId/kanban/v1/boards/:boardId/columns
POST   /api/projects/:projectId/kanban/v1/boards/:boardId/columns
PATCH  /api/projects/:projectId/kanban/v1/boards/:boardId/columns/:columnId
DELETE /api/projects/:projectId/kanban/v1/boards/:boardId/columns/:columnId

GET    /api/projects/:projectId/kanban/v1/boards/:boardId/cards
POST   /api/projects/:projectId/kanban/v1/columns/:columnId/cards
PATCH  /api/projects/:projectId/kanban/v1/boards/:boardId/cards/:cardId
DELETE /api/projects/:projectId/kanban/v1/boards/:boardId/cards/:cardId
```

#### WebSocket Events
```
WS     /api/events                # Real-time change notifications
```

---

## WebSocket Event System

### Connection

Client connects to `ws://localhost:5175/api/events` and receives:
```json
{"type": "hello"}
```

### Event Types

The server broadcasts change events to all connected clients:

```typescript
type ChangeEvent = 
  | { type: "projectsChanged" }                      // Project list updated
  | { type: "workspaceChanged", projectId: string }  // Kanban data changed
  | { type: "settingsChanged" }                      // Settings updated
  | { type: "aiConfigChanged" }                      // AI config updated
```

### Frontend Handling

The frontend **does not** currently auto-refresh on events. Events are received but not processed.

**Future enhancement**: Subscribe to workspace events and invalidate RTK Query cache:
```typescript
socket.addEventListener('message', (event) => {
  const msg = JSON.parse(event.data)
  if (msg.type === 'workspaceChanged') {
    dispatch(kanbanApi.util.invalidateTags([{ type: 'Board', id: msg.projectId }]))
  }
})
```

---

## Component Structure

```text
web/src/
├── app/
│   └── App.tsx                    # Root component, routing
├── core/
│   ├── shell/
│   │   ├── AppShell.tsx          # Layout wrapper
│   │   ├── Sidebar.tsx           # Navigation sidebar
│   │   └── TopBar.tsx            # Top navigation bar
│   ├── plugin/
│   │   ├── registry.ts           # Plugin registration system
│   │   └── types.ts              # Plugin type definitions
│   └── settings/
│       └── theme.ts              # Theme hook and picker
└── plugins/
    ├── projects/
    │   ├── ProjectPage.tsx       # Project detail view
    │   ├── ProjectsSidebar.tsx   # Project list in sidebar
    │   ├── board/
    │   │   ├── KanbanBoard.tsx   # Main board container
    │   │   ├── BoardTabs.tsx     # Board switcher
    │   │   ├── KanbanColumn.tsx  # Column component
    │   │   └── KanbanCard.tsx    # Card component
    │   ├── card/
    │   │   ├── CardDialog.tsx    # Card edit dialog
    │   │   ├── cardForm.ts       # Pure form reducer
    │   │   └── CardFields.tsx    # Form fields
    │   └── assistant/
    │       ├── DraftWithAI.tsx   # AI drafting UI
    │       └── ActivityPanel.tsx # AI progress display
    └── overview/
        └── OverviewPage.tsx      # Dashboard home
```

---

## Design Patterns

### 1. Plugin Architecture

The application uses a plugin system where features register routes and sidebar sections:

```typescript
// plugins/projects/index.tsx
export const projectsPlugin: Plugin = {
  id: 'projects',
  name: 'Projects',
  routes: [
    { path: '/projects/:id', element: <ProjectPage /> }
  ],
  sidebarSections: [ProjectsSidebar],
  navItems: [{ to: '/projects', icon: 'folder', label: 'Projects' }]
}
```

### 2. Pure Module Pattern

Pattern used everywhere: **a pure module next to the component**. `cardForm.ts`, `tracker.ts`, `boardIndex.ts` hold the decisions; the `.tsx` next to them only renders.

Take "move a sub-task to another column":

1. **`@mvp/kanban-model`** — `buildBoardIndex(cards, columns)` already knows the card's parent, its column name and its family colour. Pure function, tested with plain data.
2. **`@mvp/state`** — `useMoveCardMutation()` (in `api/kanbanApi.ts`) sends the `PATCH`; the `Card` tag is invalidated so the list refetches.
3. **`src/plugins/projects/board/`** — `KanbanColumn` handles the drop, calls the mutation; `KanbanCard` reads the index to show the breadcrumb and the colour. No logic beyond wiring.

Rule of thumb when adding code: _does it need the DOM or React?_ No → `kanban-model` (if it is about board data) or `state` (if it is about fetching/remembering). Yes, and it is reusable and knows nothing about kanban → `design-system`. Otherwise → the plugin.

### 3. Component Keys for Remounting

When switching projects, components use `key` prop to force React remount:

```tsx
<KanbanBoard key={`${projectId}-${boardId}`} projectId={projectId} />
```

This ensures:
- State resets completely
- RTK Query hooks reinitialize
- No stale data from previous project

### 4. Actor Isolation (Backend)

The Swift backend uses actors for thread-safe state management:

```swift
actor SQLiteDatabasePool {
  private var open: [String: SQLiteDatabase] = [:]
  
  func database(at path: String) async -> Database {
    // Actor ensures serial access to cache
  }
}
```

### 5. Lazy Loading

Workspace databases are created **on-demand**:
- Not loaded at server startup
- Created when project is first accessed
- Cached in pool for subsequent requests
- Migrations run on first access

---

## Performance Considerations

### Frontend

- **RTK Query caching**: Reduces redundant API calls
- **Component memoization**: React.memo for expensive renders
- **Key-based remounting**: Prevents state pollution between projects

### Backend

- **Connection pooling**: Reuses database connections
- **Actor serialization**: Prevents race conditions but can bottleneck under high load
- **Thread pool size**: Configurable per-connection concurrency (default: 2 threads)

### Known Bottlenecks

1. **Actor queue buildup**: Many concurrent workspace accesses serialize through `SQLiteDatabasePool`
2. **Migration blocking**: First access to workspace runs migrations while holding actor lock
3. **Sequential queries**: Workspace load runs 5 queries sequentially (can be parallelized)

**See**: `DATABASE_FIX_PLAN.md` for solutions to these issues.

---

## Testing

- `pnpm test` runs every package (`packages/*/src/**/*.test.*` and `src/**/*.test.*`).
- UI tests stub the server with `stubApi()` from `@mvp/state/testing`: a `fetch` stub keyed by `METHOD /api/path`, which also answers server-sent events for the AI stream.
- Pure modules are tested with plain objects — no rendering, no store.

Each package has its own `tsconfig.json` (extending `tsconfig.base.json`) so it type-checks alone: `pnpm --filter mvp-dashboard exec tsc -p packages/state/tsconfig.json --noEmit`.

---

## Development Workflow

### Adding a New Feature

1. **Backend**: Add route/controller in `Sources/DashboardServer/Routes/`
2. **API**: Add RTK Query endpoint in `web/packages/state/src/api/`
3. **Component**: Create component in `web/src/plugins/[feature]/`
4. **Plugin**: Register in `src/app/plugins.ts`
5. **Types**: Update shared types in `web/packages/kanban-model/`

### Adding a Plugin

1. Endpoints and state go in `packages/state` (a file under `api/`, exported from `index.ts`).
2. Pure helpers go in `packages/kanban-model` when they are about board data.
3. `src/plugins/<name>/index.tsx` exports a `DashboardPlugin` (`id`, `name`, `nav`, `routes`, optional `sidebar`); add it to `src/app/plugins.ts`.

---

## Security Considerations

### Current State (Development)

- ⚠️ **No authentication**: All endpoints are public
- ⚠️ **No authorization**: Any client can access any project
- ⚠️ **Local-only by default**: Binds to `127.0.0.1`

### Deployment Considerations

For production use:
1. Add authentication middleware
2. Implement project ownership/permissions
3. Use HTTPS (reverse proxy)
4. Configure CORS appropriately
5. Rate limiting on API endpoints

---

## Troubleshooting

### "Connection request timed out"

**Symptom**: Database timeouts under load  
**Cause**: Actor serialization bottleneck + unbounded connection cache  
**Fix**: See `DATABASE_FIX_PLAN.md` for complete solution

### "Previous board still visible after switching projects"

**Symptom**: Old board data persists when navigating to different project  
**Cause**: Component state not resetting, missing `key` prop  
**Fix**: Ensure `<KanbanBoard key={projectId}>` uses project-specific key

### Cards won't drag

**Symptom**: Drag and drop not working  
**Cause**: Interactive elements inside card interfering with drag events  
**Fix**: Ensure buttons have `onMouseDown` stop propagation and card has `user-select: none`

### WebSocket disconnects frequently

**Symptom**: Events stop flowing, "hello" message repeats  
**Cause**: Connection pool exhaustion or backend crash  
**Fix**: Check server logs, ensure `shutdownAll()` is called on server stop

---

## Related Documentation

- Backend: [Server Architecture](../server/architecture.md)
- Backend: `DATABASE_FIX_PLAN.md` - Database performance fixes
- Backend: `DEBUG.md` - Port and process debugging
- Root: `README.md` - Project setup and tasks
- Design System: `web/packages/design-system/README.md`
- State: `web/packages/state/README.md`
- Model: `web/packages/kanban-model/README.md`
