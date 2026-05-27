# SkillPreview Bug Triage / Fix Verification - 2026-05-27

> 状态：🟢 已修复并通过 DevAgent / test runner 验证。本文保留原始复现证据，并追加修复后的验收记录。

## Scope

本轮目标：

- 修复用户在 `skill_preview.tscn` 和 `demo_frontend` 中看到的问题。
- 用 `run-dev-scene` / DevAgent 对关键路径做修复后验收。
- 把原始复现路径、修复证据和剩余边界记录在同一份文档里。

明确不做：

- 本轮不把有限 DevAgent 复现误写成全技能 sweep 已完成。
- 本轮不做全技能逐帧截图矩阵；截图只覆盖用户点名的问题。

## Evidence Sessions

| Session | 覆盖 | 关键证据 |
|---|---|---|
| `skill-preview-bug-hunt-20260527` | facing + summon totem | `outbox.jsonl` 中 `F08-timeline`, `S19-timeline`; 截图 `S33-cap400-summon-replay-reset-400ms.png`, `S35-cap1200-summon-replay-reset-1200ms.png` |
| `skill-preview-bug-hunt-firetile-20260527` | fire tile spawn/replay | `outbox.jsonl` 中 `T07-timeline`; 截图 `T11-cap400-firetile-replay-400ms.png`, `T13-cap1400-firetile-replay-1400ms.png` |
| `skill-preview-bug-hunt-cone-20260527` | grid cone debug overlay | `outbox.jsonl` 中 `C07-timeline`; 截图 `C11-cap100-grid-cone-overlay-100ms.png`, `C13-cap400-grid-cone-overlay-400ms.png` |
| `skill-preview-sweep-*-20260527` | active skill timeline sweep part 1 | 14 个主动技能的 `24-timeline`; timeline 均 loaded，除 `skill_shadow_step` 外均未产生 `actor_facing_changed` |
| `skill-preview-sweep2-*-20260527` | active skill timeline sweep part 2 | 补齐 12 个漏扫主动技能；summary 写入 `skill-preview-sweep2-summary-20260527.json` |
| `skill-preview-fixes-20260527-111740` | fix verification | `A07-timeline` / `S06-timeline` / `T26-timeline` / `C07-timeline` / `C26-timeline`; 截图 `S10-capture-capture.jpg`, `T30-capture-capture.jpg`, `C11-capture-capture.jpg`, `C30-capture-capture.jpg`; tree dumps `S11`, `T31`, `C12`, `C31` |
| `skill-preview-vfx-stutter-fix-113636` | follow-up: totem attack VFX + fire tile replay spawn stutter | `A10-timeline` / `B09-timeline`; 截图 `A12-capture-capture.jpg`, `B13-capture-capture.jpg`; tree dump `A13-tree`, `B14-tree` |
| `skill-preview-firetile-frame-final-122130` | follow-up: fire tile frame-time diagnosis + pooled replay view fix | `F08-timeline`; `godot.log` FrameDiag shows no `long_process_delta` at replay frame 4; `spawn_view cost_ms=0.22/0.23`; screenshot `F11-capture-after-replay-capture.jpg` |

Artifacts root:

```text
C:\Users\Administrator\AppData\Roaming\Godot\app_userdata\Inkmon\dev-agent\sessions\
```

## Fix Verification - 2026-05-27

Implementation summary:

- `SP-BUG-001`: active-use activation paths now call `HexFacing.face_actor_for_active_event(...)`; `skill_preview`, production `HexBattleProcedure`, and scenario harness share the same behavior.
- `SP-BUG-002` / `SP-BUG-003`: replay presentation now consumes `actorSpawned` / `actorDestroyed` as render-state lifecycle events and creates animator-owned `FrontendUnitView` nodes under `BattleAnimator/ReplayUnitsRoot`.
- `SP-BUG-003`: `fire_tile` EnvironmentActor now uses a distinct low orange disk style with `FireTile` label instead of the generic stone-wall-like box.
- `SP-BUG-004`: cone debug cues now create `FrontendConeDebugOverlayAction` with checked-cell fill polygons plus thick footprint boundary geometry; `grid_cone_cast` and `angle_cone_cast` use distinct colors.
- `SP-BUG-005`: DevAgent `pause_playback` now clears the scene playing guard so paused deterministic replay can be reset or returned to setup.

DevAgent acceptance:

| Check | Evidence |
|---|---|
| Active Strike facing | `skill-preview-fixes-20260527-111740`, `A07-timeline`: one `actor_facing_changed`, `old_direction=0`, `new_direction=5`, `reason=active_use` |
| Totem replay view | `S06-timeline`: `actorSpawned` for `configId: "Totem"`; `S11-tree`: `BattleAnimator/ReplayUnitsRoot/skill_preview_world_0_Character_19`; screenshot `S10-capture-capture.jpg` |
| Fire Tile replay view | `T26-timeline`: `actorSpawned` for `configId: "fire_tile"` / `type: "Environment"`; `T31-tree`: `BattleAnimator/ReplayUnitsRoot/skill_preview_world_0_Environment_38`; screenshot `T30-capture-capture.jpg` |
| Grid cone overlay | `C07-timeline`: `grid_cone_cast` with 18 `checked_coords`; `C12-tree`: `ConeDebugOverlay_*` with `Fill` and `Boundary`; screenshot `C11-capture-capture.jpg` |
| Angle cone overlay | `C26-timeline`: `angle_cone_cast` with 9 `checked_coords`; `C31-tree`: `ConeDebugOverlay_*` with `Fill` and `Boundary`; screenshot `C30-capture-capture.jpg` |
| Paused replay guard | After paused summon replay, `T00-reset-after-paused-summon` returned `ok=true`; `T00b-enter-setup-after-paused` returned `ok=true` |
| Totem attack VFX follow-up | `skill-preview-vfx-stutter-fix-113636`, `A10-timeline`: 4 个 `totem_attack` stageCue；`A13-tree`: `AttackVFX_*` with `ArrowMesh` / `TrailMesh`; screenshot `A12-capture-capture.jpg` |
| Fire Tile replay spawn snap follow-up | `skill-preview-vfx-stutter-fix-113636`, `B09-timeline`: `actorSpawned` frame 4 at position `[2,0,0]`; `B14-tree`: `BattleAnimator/ReplayUnitsRoot/skill_preview_world_0_Environment_23`; screenshot `B13-capture-capture.jpg` |
| Fire Tile frame-time follow-up | `skill-preview-firetile-frame-diag-120600`: before pooling, frame 4 spawn was followed by `long_process_delta real_delta_ms≈140`; position gap stayed `0.000`; `skill-preview-firetile-frame-final-122130`: after pooling, no frame-4 long delta and spawn view cost dropped to `0.22/0.23ms` |

Test runner acceptance:

```powershell
./tools/run_tests.ps1 hex/skills hex/frontend hex/skill-preview
./tools/run_tests.ps1 hex/regression all-required
```

Both commands passed: first run `PASS 22 / FAIL 0 / TIMEOUT 0`; second run `PASS 19 / FAIL 0 / TIMEOUT 0`.

## Active Skill Sweep - 2026-05-27

本轮另跑了 active skill timeline sweep，方式是复用 SkillPreview preset，把第一个 keyframe 替换为目标技能并读取 timeline。配合上面的 targeted sessions，覆盖 `logic/abilities/active/` 下全部 29 个 `skill_*` active config。

注意：这只是 timeline / setup sweep，不等价于每个技能都做了逐帧视觉截图验收。截图只覆盖用户点名的问题。

| Skill | Timeline events | `actor_facing_changed` | 备注 |
|---|---:|---:|---|
| `skill_strike` | 见 `F08-timeline` | 0 | targeted facing repro |
| `skill_fireball` | 12 | 0 | projectile / ranged actor target |
| `skill_precise_shot` | 12 | 0 | ranged actor target |
| `skill_chain_lightning` | 26 | 0 | multi-target actor target |
| `skill_shadow_step` | 8 | 1 | 控制组；该技能本身会改朝向 |
| `skill_cleanse` | 5 | 0 | self / ally utility |
| `skill_crushing_blow` | 7 | 0 | melee actor target |
| `skill_expose` | 6 | 0 | melee actor target |
| `skill_stun` | 8 | 0 | control / actor target |
| `skill_silence` | 8 | 0 | control / actor target |
| `skill_break` | 9 | 0 | control / actor target |
| `skill_swap` | 7 | 0 | displacement / actor target |
| `skill_piercing_line` | 7 | 0 | line / coord target |
| `skill_grid_cone` | 见 `C07-timeline` | 0 | grid cone / coord target |
| `skill_angle_cone` | 7 | 0 | cone / coord target |
| `skill_holy_heal` | 6 | 0 | ally target |
| `skill_lifesteal` | 9 | 0 | melee actor target |
| `skill_knockback_punch` | 14 | 0 | melee actor target |
| `skill_execute` | 9 | 0 | melee actor target |
| `skill_magical_shield` | 5 | 0 | self utility |
| `skill_physical_shield` | 5 | 0 | self utility |
| `skill_poison` | 18 | 0 | melee actor target |
| `skill_stance` | 8 | 0 | self utility |
| `skill_summon_totem` | 见 `S19-timeline` | 0 | mid-spawn `Character` |
| `skill_spawn_fire_tile` | 见 `T07-timeline` | 0 | mid-spawn `Environment` |
| `skill_surge` | 11 | 0 | self utility |
| `skill_swift_strike` | 11 | 0 | melee actor target |
| `skill_wall_breaker` | 5 | 0 | melee actor target in this sweep |
| `skill_ward` | 5 | 0 | self utility |

## Bugs

### SP-BUG-001 - Active attack / cast does not turn caster toward target

Severity: P1.

User-visible behavior:

- In `skill_preview`, when casting at a target, caster should face that target.
- In `demo_frontend`, move changes facing, but basic attack appears not to.

Expected contract:

- `HexFacing` documents: active attack / cast should `face toward target`.
- Move already follows this path through `start_move_action.gd`.

DevAgent reproduction:

- Session: `skill-preview-bug-hunt-20260527`.
- Setup: caster at `(0,0)`, enemy at `(0,1)`, `skill_strike @ 0ms`.
- Expected: actor facing changes from EAST to SOUTHEAST before / at active use.
- Actual: `F08-timeline` contains `abilityGranted`, `executionActivated`, `stageCue`, `damage`, `basic_attack_landed`, but no `actor_facing_changed` event.
- Active sweep: all actor / coord target skills checked outside the self-only utility cases produced 0 `actor_facing_changed` events, except `skill_shadow_step` which produced 1 and should stay a control case.

Code audit notes:

- `addons/logic-game-framework/example/hex-atb-battle/logic/hex_facing.gd` already has `face_target_action()`.
- `addons/logic-game-framework/example/hex-atb-battle/logic/actions/start_move_action.gd` calls `HexFacing.face_actor_toward(...)`.
- Current active skills checked in this pass do not call `HexFacing.face_target_action()`; `rg face_target_action` finds only the helper definition.

Fix resolution:

- Chosen path: central example-layer active-use hook, not per-skill boilerplate.
- Added `HexFacing.face_actor_for_active_event(...)` and called it from production `HexBattleProcedure`, `SkillPreviewProcedure`, and `SkillScenarioHarness`.
- Added scenario coverage via `facing_active_use_scenario.gd`.
- Verified in DevAgent `A07-timeline`: `actor_facing_changed` old `EAST(0)` -> new `SOUTHEAST(5)`, reason `active_use`.

### SP-BUG-002 - Mid-battle spawned Totem has timeline data but no visible unit view in replay

Severity: P1.

User-visible behavior:

- `skill_summon_totem` should visibly create a totem unit / unit view in `skill_preview`.
- User did not see the generated unit.

DevAgent reproduction:

- Session: `skill-preview-bug-hunt-20260527`.
- Setup: `[builtin] 01_caster_strike`, replace keyframe with `skill_summon_totem @ 0ms`.
- Timeline evidence: `S19-timeline` has `actorSpawned` at frame `4` for `configId: "Totem"` / `displayName: "图腾"` / `type: "Character"`.
- Visual evidence: paused replay screenshots at frame `4` and frame `12` do not show a separate totem unit view:
  - `screenshots\S33-cap400-summon-replay-reset-400ms.png`
  - `screenshots\S35-cap1200-summon-replay-reset-1200ms.png`

Observed side note:

- In the same run, `wait_for_idle` timed out while `timeline` was already available and later `playback_state` reached ended. This is likely a DevAgent / paused playback guard issue, not the primary gameplay bug.

Fix resolution:

- `FrontendRenderWorld` now applies `actorSpawned` / `actorDestroyed` as replay lifecycle side effects.
- `FrontendBattleAnimator` owns replay-only unit views under `BattleAnimator/ReplayUnitsRoot`.
- Verified in DevAgent `S11-tree`: spawned Totem has a `FrontendUnitView` at `BattleAnimator/ReplayUnitsRoot/skill_preview_world_0_Character_19`.

### SP-BUG-003 - Fire Tile actor spawns in timeline but does not have a clear persistent unit / environment view

Severity: P1/P2.

User-visible behavior:

- User grouped this with summon-like skills: generated object is not visible as a corresponding unit view.

DevAgent reproduction:

- Session: `skill-preview-bug-hunt-firetile-20260527`.
- Setup: `[builtin] 01_caster_strike`, replace keyframe with `skill_spawn_fire_tile @ 0ms`, target enemy coord.
- Timeline evidence: `T07-timeline` has `actorSpawned` at frame `4` for `configId: "fire_tile"` / `displayName: "火焰地形"` / `type: "Environment"`.
- Visual evidence:
  - `screenshots\T11-cap400-firetile-replay-400ms.png`
  - `screenshots\T13-cap1400-firetile-replay-1400ms.png`
- Screenshot shows floating text / damage feedback, but not a clear persistent environment actor view comparable to a spawned unit.

Fix resolution:

- Shares the same mid-spawn replay lifecycle fix as SP-BUG-002.
- `fire_tile` EnvironmentActor now uses a distinct low orange disk and `FireTile` label.
- Verified in DevAgent `T31-tree`: spawned Fire Tile has a `FrontendUnitView` at `BattleAnimator/ReplayUnitsRoot/skill_preview_world_0_Environment_38`.

### SP-BUG-004 - Cone debug overlay shows markers but not readable range fill + boundary

Severity: P2.

User-visible behavior:

- User wants to see both:
  - which cells are inside the cone / checked area;
  - the cone boundary / outline.
- Current implementation looks like the intended design was misunderstood.

DevAgent reproduction:

- Session: `skill-preview-bug-hunt-cone-20260527`.
- Setup: `skill_grid_cone @ 0ms`, fixed target coord `(3,0)`.
- Timeline evidence: `C07-timeline` stageCue `grid_cone_cast` includes `params.checked_coords` with 18 cells, `origin_coord`, `target_coord`, `range`, `cast_direction`, and `direction_sector`.
- Visual evidence: `screenshots\C11-cap100-grid-cone-overlay-100ms.png` shows many small `▲` markers on cells, but no filled cell area and no cone boundary.
- Representative sweep also covered `skill_angle_cone`: timeline loaded with a single cone `stageCue`, but the same visualizer path is used by `angle_cone_cast`, so it shares the marker-only limitation unless the visualizer is redesigned.

Code audit notes:

- `stage_cue_visualizer.gd` currently implements cone debug overlay by translating `checked_coords` into `FrontendFloatingTextAction` marker text `▲`.
- There is no boundary / outline action, and no grid-cell fill layer distinct from hit targets.

Fix resolution:

- Replaced floating text markers with `FrontendConeDebugOverlayAction` and `FrontendConeDebugOverlayView`.
- Overlay renders translucent checked-cell fill plus thick footprint boundary.
- Grid cone and angle cone use distinct colors.
- Verified in DevAgent `C12-tree` / `C31-tree`: both have `ConeDebugOverlay_*` with `Fill` and `Boundary`.

### SP-BUG-005 - DevAgent paused replay guard can leave scene hard to reset

Severity: P3 tooling.

Observed while collecting evidence:

- After deterministic replay pause / step for summon evidence, `playback_state` reported `is_playing: false`, but later mutation ops returned `cannot reset while playing` / `cannot enter setup mode while playing`.
- This forced a Godot process restart before continuing the next skill check.

Fix resolution:

- `dev_agent_pause_playback()` now clears the DevAgent mutation guard (`_is_playing = false`) after pausing the animator.
- Verified in DevAgent: after paused replay, `reset_battle` and `enter_setup_mode` both returned `ok=true`.

### SP-BUG-006 - Totem passive attack applies damage but has no attack VFX cue

Severity: P1.

User-visible behavior:

- `skill_summon_totem` creates a totem, and the totem later attacks.
- The target loses HP, but replay has no visible totem attack effect.

DevAgent reproduction:

- Session: `skill-preview-vfx-stutter-fix-113636`.
- Setup: enemy idx `1` at `(3,0)`, HP `500`; caster keyframe `skill_summon_totem`; `max_ticks=500`, `speed=1`.
- Run: `start_battle` -> `wait_for_idle` -> `timeline max_events=400`.
- Before fix expectation failure: damage events exist from the totem, but there is no presentation cue for `StageCueVisualizer` to turn into attack VFX.
- Fix verification: `A10-timeline` contains 4 `stageCue` events with `cueId: "totem_attack"` from the spawned totem to the enemy.
- Visual verification: paused replay stepped to frame `34`; `A13-tree` contains `AttackVFX_*`, `ArrowMesh`, and `TrailMesh`; screenshot `A12-capture-capture.jpg`.

Code audit notes:

- `totem_attack.gd` emitted damage directly from the passive action.
- `stage_cue_visualizer.gd` had no cue mapping for `totem_attack`.

Fix resolution:

- `totem_attack.gd` now emits `GameEvent.StageCue` before damage.
- `stage_cue_visualizer.gd` maps `totem_attack` to an amber impact VFX.
- Scenario and production replay smoke now assert the totem attack cue exists.

### SP-BUG-007 - Mid-battle Fire Tile replay spawn creates a visible frame-time spike

Severity: P1/P2.

User-visible behavior:

- `skill_spawn_fire_tile` replay shows the spawned fire tile / floating text path visibly stuttering around spawn time.
- The issue is replay-stable and reproduces every run.

DevAgent reproduction:

- Session: `skill-preview-vfx-stutter-fix-113636`.
- Setup: enemy idx `1` at `(2,0)`, HP `500`; caster keyframe `skill_spawn_fire_tile`, target enemy index `0`; `max_ticks=500`, `speed=1`.
- Run: `start_battle` -> `wait_for_idle` -> `timeline max_events=240` -> `replay_battle` -> `pause_playback` -> step twice by `100ms`.
- Timeline evidence: `B09-timeline` has `actorSpawned` at frame `4` for `configId: "fire_tile"`, `type: "Environment"`, `position: [2,0,0]`.
- First follow-up diagnosis: `skill-preview-firetile-frame-diag-120600` showed `fire_tile_snap` and `unit_position_gap gap=0.000`, so the final root was not residual position lerp.
- Frame-time evidence before pooling: the same session logged `long_process_delta frame=4 real_delta_ms≈140` immediately after replay frame 4, where `actorSpawned` creates the Fire Tile view.
- Fix verification: `skill-preview-firetile-frame-final-122130` has no `long_process_delta` at replay frame 4; `spawn_view cost_ms` dropped to `0.22/0.23`.

Code audit notes:

- `FrontendUnitView.set_world_position()` intentionally smooths toward `_target_position`, so first fix added `snap_world_position()` for spawn placement and DevAgent stepping.
- Follow-up logs showed the Fire Tile view was already snapped to the target position (`gap=0.000`), but creating / first showing the replay-only `FrontendUnitView` on replay frame 4 still caused an abnormal process delta.

Fix resolution:

- Added `FrontendUnitView.snap_world_position()` to set `_target_position`, `_smoothed_position`, and `position` atomically.
- Replay `actorSpawned` and initial world hydration use snap placement instead of smoothed placement.
- `FrontendBattleAnimator.load()` now prebuilds replay-only views for `actorSpawned` events; `reset()` hides/deactivates them instead of freeing them; frame 4 reuses the pooled view instead of constructing mesh/material/labels during playback.
- Added targeted `[Frontend:FrameDiag]` logs for abnormal process delta, tick cost, Fire Tile spawn, and Fire Tile position gap.

## Coverage Status

Covered in this first pass:

- `skill_strike` facing through `skill_preview`.
- Active skill timeline sweep for all 29 `skill_*` configs under `logic/abilities/active/`.
- `skill_summon_totem` replay visibility.
- `skill_summon_totem` passive attack VFX.
- `skill_spawn_fire_tile` replay visibility.
- `skill_spawn_fire_tile` replay spawn-frame snap placement.
- `skill_grid_cone` debug overlay.
- `demo_frontend` basic attack facing was not separately run, but likely shares SP-BUG-001 root because move uses `HexFacing.face_actor_toward` and Strike does not emit `actor_facing_changed`.

Not yet swept:

- Per-skill visual screenshot matrix / edge-case presets in `skill_preview`.
- `skill_angle_cone` visual comparison screenshot. Timeline was covered; screenshot capture still pending.
- `demo_frontend` windowed replay capture.
- `skill_wall_breaker` against an Environment target. This sweep covered the Character target path only.

## Remaining Boundaries

- 本 triage 中 7 个已记录 bug 均已有修复和 DevAgent 验收证据。
- 尚未做全技能逐帧截图矩阵；当前截图覆盖用户点名的 Strike / Totem / Fire Tile / grid cone / angle cone。
- `demo_frontend` 未单独窗口截图，但其 production activation path 已接入同一个 `HexFacing.face_actor_for_active_event(...)`，并由 `hex/frontend` / `hex/regression` smoke 覆盖不崩。
