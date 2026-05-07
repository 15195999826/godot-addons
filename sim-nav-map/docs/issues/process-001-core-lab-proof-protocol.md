# PROCESS-001: Core-vs-lab proof protocol

- Status: open
- Severity: P1
- Layer: process
- Source: codex-discussion
- Created: 2026-05-07

## Problem

When a behavior looks wrong, it is easy to blame core because the lab
uses many core primitives. That can lead to changing the wrong layer,
which both wastes time and risks regressing core invariants in pursuit
of a lab symptom.

## Protocol

1. Reproduce the issue in `rtslab/smoke` or a small lab scene.
2. Extract the exact map, obstacle layout, unit radius, start, goal,
   and query options.
3. For navigation / movement / obstruction behavior, read the relevant
   0 A.D. source files directly under `docs/references/0ad-source/`
   before choosing the fix shape. Do not rely on old AI summary notes.
4. Write a minimal core-only smoke / query using `SimNavMap` and the
   relevant core API.
5. If the core-only query returns a wrong path, wrong reachability, or
   invalid line result, fix core. Add a focused core regression smoke.
6. If the core-only query is correct and the lab still fails, fix the
   lab. Keep the policy fix in `examples/rts-pathfinding-lab/`.
7. Record which source files were checked and why the fix belongs to
   core or lab in the issue's Resolution section.

## Status

This protocol is operational guidance, not code. It is captured here so
that LAB-* issues can reference it from their "Verify before fixing"
sections without restating it. When a fix lands that exemplifies the
protocol (e.g. "we reproduced this lab bug as a core smoke and
confirmed core was fine"), link the smoke from this file as a worked
example.

## Repro

This issue has no code repro — it is process guidance. The "test" of the
protocol is whether each LAB-* fix that lands has an accompanying
core-only smoke (or an explicit note that core was checked and is fine).

LAB-* issues currently in scope and how repro pairs apply:

- [LAB-001](lab-001-default-avg-step.md) — `repro_lab_001_default_avg_step.gd` is the lab repro. Before optimizing core, write a core-only smoke that runs the equivalent path queries against `SimNavMap` directly and times them; if core-only is fast, the avg-step bug is lab policy.
- [LAB-002](lab-002-stress-long-frames.md) — same pattern. The stress repro mostly thrashes obstacle edits; a core-only smoke timing `nav_map.rebuild_dirty()` and `compute_path_result` separately should be the next step (and likely surfaces [CORE-007](core-007-static-rasterize-aabb.md) before any lab change is needed).
- [LAB-003](lab-003-active-jump-55px.md) — `repro_lab_003_max_jump.gd` provokes a 41.50 px static-escape teleport. The matching core-only check is "is `unit.position` after the obstacle drop reported as passable by `SimNavMap.is_passable_navcell`?" If yes, lab escape policy is at fault (not core).

## Worked examples

(Empty — populate as protocol is applied. First entry will land with the
first core-or-lab fix from the LAB-001/002/003 trio.)

## Cross-refs

- Source note: seeded from prior Codex discussion; active tracking is this issue.
- Smoke matrix: `../smoke-matrix.md`
- Public API boundary: `../public-api.md`
- All LAB-* issues should reference this protocol from "Verify before fixing"
