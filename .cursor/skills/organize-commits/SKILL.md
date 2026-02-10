---
name: organize-commits
description: >-
  Splits uncommitted changes into a small set of logical, single-concern git
  commits. Use when the user wants to organize changes into logical commits,
  split a large change into multiple commits, or create a series of conventional
  commits from the current working tree.
---

# Organize Changes Into Logical Commits

You organize uncommitted changes into logical, single-concern commits (e.g. one per: config, formatting, behavior, tests, docs). Follow the workflow below.

## Workflow

### 1. Inspect current state

- Run `git status` and `git diff` (and `git diff --staged` if anything is already staged).
- Note which files and areas changed (config, source, tests, docs, rules, etc.).

### 2. Group by logical concern

Group changes into **concerns**, not one commit per file. Typical groups:

| Concern            | Examples                                         | Conventional type              |
| ------------------ | ------------------------------------------------ | ------------------------------ |
| Config / tooling   | ESLint, Prettier, tsconfig, package.json scripts | `chore` or `build`             |
| Formatting only    | Blank lines, quotes, line length                 | `style` or `chore(style)`      |
| Feature / behavior | New logic, compose order, numbering              | `feat` or `fix`                |
| Tests              | New or moved tests, fixtures                     | `test`                         |
| Docs / rules       | AGENTS.md, docs content, .mdc rules, skills      | `docs`                         |
| Misc / cleanup     | Unrelated small fixes                            | `chore` or split when feasible |

If a **single file** has edits that span two concerns (e.g. code + comment), prefer one commit per concern and use `git add -p` (patch) for that file, or list the file under the dominant concern and note the mix.

### 3. Propose a commit plan

Present an ordered list of commits **before** changing the repo:

- **Scope**: which paths or hunks go in this commit.
- **Message**: conventional style `type(scope): subject` (e.g. `chore(deps): add eslint and prettier config`).
- **Body** (optional): add when the subject is not enough.

Order commits so the history reads logically (e.g. config → code → tests → docs). Ask the user to confirm or adjust the plan.

### 4. Execute commits

For each commit in order:

1. Stage only the files (or patches) for that concern: `git add <paths>` or `git add -p <file>`.
2. Commit with the agreed message: `git commit -m "type(scope): subject"` or `-m "subject"` plus `-m "body"`.
3. Proceed to the next commit.

If the user prefers to run commands themselves, output a copy-pastable list of `git add` and `git commit` steps instead of executing.

## Commit message format

- **Conventional commits**: `type(scope): subject`. Common types: `chore`, `feat`, `fix`, `docs`, `test`, `style`, `refactor`.
- **Subject**: present tense, under ~72 chars, no period at the end.
- **Body**: add when the subject is not enough to explain why or what.

Project rules may further customize this (e.g. `{{RULES_DIR}}*{{RULES_EXT}}` with "generate commit message" guidance).

## Example plan

Given unstaged changes across config, compose logic, tests, and docs:

```text
Commit 1 — chore(config): add ESLint and Prettier config
  .eslintrc.cjs, .prettierrc, package.json (scripts/lint)

Commit 2 — style: ensure blank line after frontmatter
  scripts/shared/formats.ts (or relevant formatter)

Commit 3 — feat(compose): apply order and sequential section numbers
  scripts/compose/*.ts, scripts/shared/composer.ts

Commit 4 — test(compose): consolidate and fix compose tests
  scripts/compose/__tests__/*.ts

Commit 5 — docs: update AGENTS, rules, variants and misc
  AGENTS.md, apps/docs/content/**, .cursor/rules/**, rules/**, scripts/compose/variants.ts
```

Run the five `git add` / `git commit` steps in that order.

## Checklist before finishing

- [ ] All changes are assigned to exactly one commit (no leftover unstaged edits unless intended).
- [ ] Commit messages follow conventional style and project preferences.
- [ ] Order of commits makes sense for someone reading the history later.
