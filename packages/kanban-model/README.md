# @mvp/kanban-model

The vocabulary of the board and the pure functions over it. No React, no Redux, no fetch:
everything here is a plain TypeScript function that takes data and returns data, which is
why it is the easiest place to test.

| Module          | What it holds                                                                       |
| --------------- | ----------------------------------------------------------------------------------- |
| `types.ts`      | Wire types (`Card`, `Column`, `Board`, `AICost`, …) exactly as the API sends them   |
| `board.ts`      | Grouping by column, neighbours, card family colours                                 |
| `boardIndex.ts` | `buildBoardIndex(cards, columns)`: one pass that answers hierarchy, names, progress |
| `checklist.ts`  | `- [ ]` / `- [x]` counting in a markdown description                                |
| `draft.ts`      | AI draft types and the helpers that turn a draft into card fields and cost          |
