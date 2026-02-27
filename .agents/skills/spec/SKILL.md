---
name: spec
description: Create a feature spec with individual task files. Use for features that benefit from structured planning (4+ files or unclear scope).
---

# Spec

Create a feature specification with individual task files. One skill for all planning — size-aware, so a 2-task feature gets minimal files while a 10-task feature gets full detail.

## Load Context

Before starting, read these files (if they exist):
- `AGENTS.md` — Architecture rules, naming conventions, project-specific patterns
- Any spec/task templates in `.agents/templates/` — Use if available

## Input

A feature name and description. Can be a one-liner or a detailed requirements document.

## Workflow

### 1. Understand the Feature

- Parse the feature description
- Ask clarifying questions if scope is ambiguous — **do not assume**
- Identify which users or components are affected

### 2. Research the Codebase

- Search for related existing code, modules, interfaces
- Identify patterns to follow (find a similar feature already built)
- Check any docs/ directory for architecture documentation
- Map out which layers or modules are affected

### 3. Design Backward from Goals

Before writing anything, reason backward from the finished feature:

1. **Observable truths** — Ask: "What must be TRUE when this feature works?" List 3-7 truths from the user's perspective as observable behaviors.
2. **Required artifacts** — For each truth, ask: "What must EXIST for this to be true?" (models, endpoints, services, UI components, configs)
3. **Critical connections** — For each artifact, ask: "What must be CONNECTED for this to function?" (relationships, event listeners, middleware, registrations)

This produces sharper tasks with verifiable acceptance criteria. The truths become spec acceptance criteria; the artifacts become tasks; the connections become implementation details within tasks.

### 4. Create the Spec Directory

```bash
.agents/specs/<feature-name>/
├── spec.md
├── progress.md
└── tasks/
    ├── 01-<verb>-<noun>.md
    ├── 02-<verb>-<noun>.md
    └── ...
```

### 5. Write spec.md

Copy structure from `.agents/templates/spec.md` (if available) and fill every section:

- **Problem & Goal** — crisp, one paragraph + one sentence
- **Requirements** — must have, out of scope, acceptance criteria (use the observable truths from step 3)
- **Design** — affected components, interfaces, data changes (only relevant sections)
- **Task index** — table with dependency graph, sizes, file lists
- **Edge cases** — explicit, not left for discovery
- **Known pitfalls** — codebase-specific gotchas discovered during research
- **Testing strategy** — concrete: which test types, which scenarios

**Task index requirements:**
- Tasks ordered by dependency (foundational first)
- Each task lists exact files it creates/modifies
- Dependencies are explicit (enables parallel execution)
- Mark parallelizable tasks with `[P]`
- Size estimates: S (1-2 files), M (3-5 files), L (5+ files)

### 6. Write Individual Task Files

For each task in the index, create `tasks/NN-verb-noun.md` (from template if available):

- **What** — specific about files to create/modify
- **How** — implementation approach referencing existing patterns. Code sketch for complex tasks, one sentence for simple ones. Include known pitfalls relevant to this task.
- **Files** — exact paths with create/modify markers
- **Acceptance** — observable behaviors, not vague checkboxes. Bad: "endpoint works." Good: "POST /api/items returns 201 with created item; GET /api/items returns paginated list."
- **Done** — empty checklist (filled during implementation)
- **Notes** — empty (filled during implementation)

**Size-awareness:**
- Simple task (S): How section is 1-2 sentences
- Medium task (M): How section has bullet points or a brief approach
- Complex task (L): How section has a code sketch and edge case notes

**Specificity test:** For each task file, ask: "Could a fresh agent execute this task without asking clarifying questions?" If not, add detail.

### 7. Initialize progress.md

Create `progress.md` with a `## Log` section (empty — append entries after each task is completed).

### 8. Present for Approval

Show the completed spec with:
- Summary of what will be built
- Total task count and scope estimate
- Dependency graph visualization
- Any open questions needing human input
- **Wait for approval before proceeding**

### 9. After Approval

- Update spec.md status to `in-progress`
- Create feature branch: `feat/<feature-slug>` or `fix/<feature-slug>`
- Tell the user to run `spec-loop run` to start implementing tasks

## Rules

- Every spec lives in `.agents/specs/<feature-name>/` as a directory
- Tasks are individual files in `tasks/`, not checkboxes in spec.md
- Don't over-engineer — match detail level to feature complexity
- Reference existing patterns, don't invent new ones
- If the feature is trivial (< 3 files, obvious implementation), skip the spec and just build it directly
- Specs are living documents — update them as implementation reveals new requirements
