# Spec: [Feature Name]

> Status: draft | approved | in-progress | complete
> Created: YYYY-MM-DD

## Problem

What's broken or missing. Who's affected. Why now.

## Goal

One sentence.

## Requirements

### Must Have
- Requirement 1
- Requirement 2

### Out of Scope
- Explicitly excluded

### Acceptance Criteria
- AC1: Given X, when Y, then Z
- AC2: Given X, when Y, then Z

## Design

### Data Changes

| Entity | Change | Details |
|--------|--------|---------|

### API / Interface Changes

| Method | Path / Interface | Description |
|--------|-----------------|-------------|

### Core Logic

Key business rules and algorithms.

## Tasks

Dependencies:
1 → 2 → 5
     3 → 5
     4 → 5
          6 [P]
          7 [P]

| # | Task | Size | Depends | Files |
|---|------|------|---------|-------|
| 1 | Add models | S | — | src/models/item.ts |
| 2 | Add data access | S | 1 | src/db/item.ts |
| 3 | Add validation | S | 1 | src/schemas/item.ts |
| 4 | Add service logic | M | 2 | src/services/items.ts |
| 5 | Add routes | M | 2, 3, 4 | src/routes/items.ts |
| 6 | Tests | S | 5 | tests/items.test.ts [P] |
| 7 | Migration | S | 1 | migrations/... [P] |

> S = 1-2 files. M = 3-5 files. L = 5+ files.
> [P] = parallelizable with other [P] tasks at same level.

Detail for each task in `tasks/NN-name.md`.

## Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|

## Known Pitfalls

Codebase-specific gotchas discovered during research that implementers should know upfront.

## Testing Strategy

What to test and how.

## Open Questions

- Unresolved items needing human input
