# CORE-009: Pathfinder heap is O(n) sorted-array insert

- Status: open
- Severity: P3
- Layer: core
- Source: claude-audit-2026-05-07
- Created: 2026-05-07

## Symptoms

`SimNavPathfinderHeap` is a sorted array with binary-search insert,
giving `O(n)` insert (due to array shift) and `O(1)` pop. For long-path
A* / JPS on larger grids the open-list size grows enough that the
per-insert cost becomes a measurable constant factor.

## Root cause

`addons/sim-nav-map/pathfinding/sim_nav_pathfinder_heap.gd:4-24` uses
sorted-array binary insert. There is no decrease-key support; better
costs for an existing node are handled via lazy deletion (re-push, skip
on pop if already closed). Correctness is fine; constant factor is not.

## 0 A.D. reference

`docs/references/0ad-source/source/simulation2/helpers/LongPathfinder.h:138`
uses a templated `PriorityQueueHeap<TileID, PathCost, PathCost>` that is
a binary heap backed by `std::vector`. Insert / pop are heap operations;
`promote()` still scans the heap linearly to find the tile before
re-heapifying that prefix. So 0 A.D. avoids sorted-array insert shifts, but
does not use an index map.

## Proposed fix

Two acceptable shapes:

1. **Binary heap with no decrease-key** (preserves lazy-deletion model).
   Replace the sorted array with a true binary heap stored in a
   `PackedFloat32Array` or similar. `O(log n)` insert and pop. No API
   change.
2. **Binary heap + index map** (stronger than 0 A.D., supports real
   decrease-key). Higher complexity but eliminates lazy duplicates.
   Probably overkill unless a profile shows duplicates dominate.

Default to (1). Promote to (2) only if measurement shows duplicates
matter.

## Verify before fixing

- [ ] Measure: instrument the open list size for a few representative long-path queries to confirm `n` is large enough for the change to matter
- [ ] Confirm correctness: heap output ordering must remain identical to current (`(f, h, x, y, insertion_seq, index)` tie-break per existing comments)
- [ ] Decide whether a fully-typed packed array gives a worth-it speed-up in GDScript vs an `Array[Array]`

## Repro at HEAD (smoke pending instrumentation)

**No smoke yet.** A meaningful repro requires per-operation heap timing
in `SimNavPathfinderHeap` (currently absent). Without it, the only
observable signal is total wall time of long-path queries on large
grids, which mixes A* logic, JPS, navcell access, and heap together.

Manual recipe to characterize at HEAD:

1. Build a large open navcell map (1024×1024, no obstacles).
2. Plan a long path corner to corner (`(2, 2)` → `(1021, 1021)`).
3. Time the call. Compare against a 256×256 grid with the same relative
   start/goal positions. Time should grow super-linearly with grid size
   if heap insert is `O(n)` (sorted-array shift cost dominates as open
   list grows).

**Smoke deliverable** (after instrumentation lands): a
`addons/sim-nav-map/tests/repro/repro_core_009_heap_improve.gd` that
1. records insert / pop timing on a fixed long-path query,
2. asserts the existing path output is unchanged (bit-identical),
3. records a "before" baseline today and an "after" target after the
   binary-heap change.

## Cross-refs

- [LAB-001](lab-001-default-avg-step.md) — only worth doing if measurement says heap matters at lab scale
