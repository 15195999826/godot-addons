## RtsScenario - 声明式 RTS scenario 基类 (P3.3)
##
## 与 hex example `SkillScenario` 同构, 但服务 RTS 场景: 单位寻路 / 互避障 /
## formation / 动态 obstacle / 玩家命令链路验证。
##
## 子类 override 4 个钩子声明 scenario 内容, harness 接管装配 + tick + 断言。
##
## 用法:
## ```
## class MyScenario extends RtsScenario:
##     func get_scene_config() -> Dictionary:
##         return {
##             "map_size": Vector2(600, 500),
##             "rng_seed": 42,
##             "tick_interval_ms": 50.0,
##             "buildings": [
##                 {"kind": "barracks", "team": 1, "pos": Vector2(300, 250)},
##             ],
##             "units": [
##                 {"class": RtsUnitClassConfig.UnitClass.MELEE, "team": 0, "pos": Vector2(50, 250)},
##             ],
##         }
##     func get_player_commands() -> Array[Dictionary]:
##         return [{
##             "tick": 1,
##             "kind": "move_units",
##             "team_id": 0,
##             "unit_selector": {"team": 0, "all": true},
##             "target_pos": Vector2(550, 250),
##         }]
##     func get_max_ticks() -> int:
##         return 200
##     func get_name() -> String:
##         return "scenario_my_test"
##     func assert_replay(ctx: RtsScenarioAssertContext) -> void:
##         var unit := ctx.get_units_by_team(0)[0]
##         ctx.assert_le(unit.position_2d.distance_to(Vector2(550, 250)), 50.0,
##             "unit should arrive within 50px of target")
##         ctx.assert_ge(ctx.detour_ratio(unit.get_id(), Vector2(550, 250)), 1.15,
##             "expected detour around obstacle")
## ```
##
## 决策来源: phase-3-advanced.md §P3.3
class_name RtsScenario
extends RefCounted


## scene 描述. 必填字段:
##   - "map_size": Vector2 像素尺寸 (e.g. Vector2(600, 500))
## 可选字段:
##   - "rng_seed": int (默认 0)
##   - "tick_interval_ms": float (默认 50.0; 与 P1.7 fixed-tick 33.33 不同 — scenario 用
##                                整 50ms 让 max_ticks 易算成秒)
##   - "team_configs": Dictionary[int, RtsTeamConfig] (默认 unconfigured;
##                     placement scenarios 需配 build_zone)
##   - "buildings": Array[Dictionary] - 起手建筑列表
##                  每条 {"kind": String, "team": int, "pos": Vector2,
##                        "hp_override": float (可选)}
##                  kind 走 RtsBuildingConfig.KIND_* 字符串
##   - "units": Array[Dictionary] - 起手单位列表
##              每条 {"class": int (UnitClass), "team": int, "pos": Vector2,
##                    "stance": int (可选, 默认 strategy 默认值)}
func get_scene_config() -> Dictionary:
	return {}


## 玩家命令列表. 每条 Dictionary 必填:
##   - "tick": int (procedure._current_tick == tick 时 apply)
##   - "kind": String ("move_units" | "place_building" | "add_static_obstacle")
##   - "team_id": int
## kind = "move_units":
##   - "unit_selector": Dictionary - 见 §unit_selector
##   - "target_pos": Vector2
## kind = "place_building":
##   - "building_kind": String (RtsBuildingConfig.KIND_*)
##   - "pos": Vector2
## kind = "add_static_obstacle" (绕过 build_zone 直接 add_actor + 写 grid blocking;
##         给 dynamic_obstacle scenario 用):
##   - "building_kind": String
##   - "pos": Vector2
##   - 不消耗 team_resources, 不走 RtsBuildingPlacement 校验
##
## §unit_selector
## ```
## {"team": int, "all": true}                  # 选 team 所有 alive units (按 spawn 顺序)
## {"team": int, "indices": Array[int]}        # 按 spawn 顺序选第 indices[i] 个 unit
## ```
func get_player_commands() -> Array[Dictionary]:
	var empty: Array[Dictionary] = []
	return empty


## 安全上限 ticks. 抵达后 harness 强制结束 — assert_replay 仍跑 (通常 scenario 应在更早收口)。
##
## 默认 200 (50ms × 200 = 10s 真实时间)。
func get_max_ticks() -> int:
	return 200


## scenario 名 (失败报告 + 录像 metadata 用)。
func get_name() -> String:
	return "rts_scenario"


## 断言钩子. harness 跑完战斗 + 构造 ctx 后调用一次。
##
## scenario 通过 ctx.assert_* / ctx.fail() 表达断言; ctx.has_failed() 决定 harness.run 返回 success。
##
## 不要在 assert_replay 内部修改 actor / world 状态 — 仅读 + 断言。
func assert_replay(_ctx: RtsScenarioAssertContext) -> void:
	pass
