# PLANS.md

This repository uses execution plans for long-running Codex work. An execution plan is a living, self-contained implementation document that allows a future agent or human to resume the task without relying on hidden context.

Use an ExecPlan for any task that includes one or more of the following:

* GitHub Actions build repair.
* Multi-step debugging.
* iOS/Gecko/Reynard feature work.
* JIT, TXM, DDI, pairing, SideStore, or LocalDevVPN work.
* Page Zoom implementation.
* Any task expected to require more than one commit or more than one build/test cycle.

## Non-negotiable requirements

Every ExecPlan must:

* Be self-contained.
* State the purpose and user-visible outcome.
* Define success criteria before implementation.
* Track progress continuously.
* Record surprises and discoveries.
* Record decisions and why they were made.
* Include exact commands run and relevant outputs.
* Include links or identifiers for GitHub Actions runs.
* Distinguish verified facts from hypotheses.
* Never leave `in_progress` work unaccounted for at a stopping point.
* End with a clear outcome and retrospective.

## Required ExecPlan skeleton

Create task-specific plans under `.agent/execplans/`.

Use this filename pattern:

```text
.agent/execplans/YYYYMMDD_short-task-name.md
```

Use this template:

```md
# <Short task title>

This ExecPlan follows the repository root `PLANS.md`. It must remain current as work proceeds.

## Purpose / Big Picture

Explain what user-visible outcome this work enables and why it matters.

## Success Criteria

- [ ] Criterion 1.
- [ ] Criterion 2.
- [ ] Criterion 3.

## Current State

Describe the current repo state, branch, important files, latest known failure or target behavior, and exact evidence. Include run IDs, commit SHAs, paths, and artifact names where relevant.

## Constraints

List hard constraints, do-not rules, platform limitations, and assumptions.

## Progress

- [ ] Initial context inspected.
- [ ] Plan created.
- [ ] First implementation step completed.
- [ ] Verification run completed.
- [ ] Final outcome recorded.

Update this section at every meaningful stopping point.

## Surprises & Discoveries

Record unexpected findings with short evidence snippets. Include exact error lines, command outputs, or file paths when useful.

## Decision Log

- Decision:
  - Reason:
  - Evidence:
  - Consequence:

## Plan of Work

Describe the implementation sequence in prose. Name exact files and expected changes. Keep it concrete.

## Concrete Steps

List exact commands and expected observations.

## Validation

State exactly how success will be verified. Include local checks, GitHub Actions checks, artifact inspection, and manual device checks where applicable.

## Recovery / Fallbacks

Document what to do if each likely failure occurs. Include when to use a fallback versus when to continue repairing the primary path.

## Outcomes & Retrospective

Fill this in at completion or stopping point:

- What changed:
- What passed:
- What failed or remains unknown:
- Artifact/run/commit identifiers:
- Recommended next action:
```

## Working rule

When implementing an ExecPlan, do not ask the user for “next steps” after each milestone. Continue to the next milestone autonomously until the task is complete, blocked by a real external limitation, or the available run time is exhausted. If blocked, record the blocker, evidence, and the smallest precise question needed to proceed.
