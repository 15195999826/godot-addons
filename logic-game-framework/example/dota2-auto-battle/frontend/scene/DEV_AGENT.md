# DEV_AGENT — dota2_lane_battle

Development-only DevAgent contract for the dota2-auto-battle M1 visible scene.
**Not** a regression test path; do not wire into `tools/run_tests.ps1` or CI.

## Classification (Step 0)

Validates **presentation / business-logic data flow** — autonomous ARAM lane
battle: two waves spawn, sim-nav march, aggro→chase→Ability basic attack, HP
bars, attack/death visual feedback, rich debug panel. No UI-loop / UX target,
so every named op is a **direct function call** into the scene's dev hooks
(the scene's private logic clock owns realtime ticking; step/run ops pause it
then advance the procedure deterministically). Genuine visual targets are
checked with the generic `capture`; raw input ops are the escape hatch.

## Launch

```bash
SESS_NAME="<task-slug>"
SESS_DIR="$APPDATA/Godot/app_userdata/Inkmon/dev-agent/sessions/$SESS_NAME"
rm -rf "$SESS_DIR" && mkdir -p "$SESS_DIR"
godot --path C:/GodotPorjects/inkmon-godot \
  res://addons/logic-game-framework/example/dota2-auto-battle/frontend/scene/dota2_lane_battle.tscn \
  -- --dev-agent --dev-agent-session=$SESS_NAME \
  > "$SESS_DIR/godot.log" 2>&1
```

Run in background; wait for `$SESS_DIR/outbox.jsonl` to exist (~1–3 s) before
the first op. Without `--dev-agent` the scene is a normal F6 demo (zero DevAgent
nodes created).

## Named ops (all direct-call)

### Observation (read-only Dictionary)

| op | returns (`data`) |
|---|---|
| `state` | `tick`, `logic_time_ms`, `paused`, `ended`, `result`, `left_alive`, `right_alive`, `total_alive`, `catchup_frames`, `debt_drop_frames`, `recent_events[]`, `actors[]` (`id,team,type,hp,max_hp,x,y,alive,intent,target,movement,on_cooldown,attacking`) |

### Action / mutation (changes state; returns `ok` + post-state in `data`)

| op | args | snapshot fields that change after success |
|---|---|---|
| `set_paused` | `{value:bool}` | `paused` |
| `step_ticks` | `{count:int}` | `tick`, `logic_time_ms`, `actors[*]` (pos/hp/intent/movement), `left_alive`/`right_alive`, `recent_events`, `result`/`ended` (if it ends), plus `data.stepped` |
| `run_until` | `{event:str,max_ticks:int}` | same as `step_ticks` + `data.reached`, `data.stepped`, `data.waited_for`. `ok=true` only if the event kind was seen |
| `restart` | — | resets `tick→~1`, `result→""`, `ended→false`, `actors` re-spawned, counters reset |

`event` for `run_until` is a canonical `Dota2BattleEvents` kind, e.g.
`dota2_target_acquired`, `dota2_attack_started`, `dota2_damage_applied`,
`dota2_unit_died`.

### Raw escape hatch (generic bridge ops)

`capture` (visual confirmation — lane layout / HP bars / attack-death feedback),
`tap_key` (Space=pause, R=restart real-key path), `click_at`, `inspect_tree`,
`inspect_controls`, `dump_node`, `wait_frames`. Every scene-op response also
carries `data.supported_ops`.

## Recommended visual-validation loop

1. `{"op":"scene","name":"state"}` — read `data.supported_ops` + initial 8-actor
   spawn (4+4, left/right).
2. `{"op":"capture","label":"spawn"}` — ARAM lane formation at t≈1.
3. `{"op":"scene","name":"run_until","args":{"event":"dota2_damage_applied","max_ticks":400}}`
   — fast-forward to first damage (units engaged).
4. `{"op":"capture","label":"engage"}` — marching/chase + HP bars dropping +
   attack feedback (yellow arc on `attacking`).
5. `{"op":"scene","name":"run_until","args":{"event":"dota2_unit_died","max_ticks":400}}`
   then `{"op":"capture","label":"first_death"}` — death visual (greyed unit).
6. `{"op":"scene","name":"step_ticks","args":{"count":800}}` then
   `{"op":"capture","label":"resolved"}` — debug panel shows result + recent
   events.

## Caveats

- `step_ticks`/`run_until` set `paused=true` (they own stepping); call
  `set_paused {value:false}` to resume realtime if you want the clock back.
- Catch-up telemetry (`catchup_frames`/`debt_drop_frames`) only moves under the
  realtime clock with long render stalls — deterministic stepping won't bump it
  (by design; that path is observed live, not stepped).
- Headless window defaults small; this scene's camera fits the lane to the
  viewport, so `capture` is readable at the default 960px JPEG.
