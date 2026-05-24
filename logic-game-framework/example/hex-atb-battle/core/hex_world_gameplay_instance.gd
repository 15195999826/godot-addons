## HexWorldGameplayInstance - 六边形战斗世界 Instance
##
## 继承 WorldGameplayInstance, 承担六边形战斗系统的 actor registry / grid / systems 管理。
## 战斗推进由 HexBattleProcedure 承担 —— 参见 hex_battle_procedure.gd。
##
## 现有 HexBattle(example/hex-atb-battle/logic/hex_battle.gd) 保留为 thin 兼容子类,
## 不破坏现有调用端 (scenario harness / main.gd / SimulationManager 等)。
class_name HexWorldGameplayInstance
extends WorldGameplayInstance


# ========== 信号 ==========

## 战斗结束后发布逻辑层 actor 终态 snapshot, 供 view-logic 一致性 oracle 对账。
## 仅在 debug build 下 emit (OS.has_feature("debug"))。release 包不算不发, 零开销。
##
## 与 framework 的 battle_finished 配对发出: 同一次 tick 内, base GI 的 handler 先于
## 子类 (HexDemoWorldGI / SkillPreviewWorldGI) 的 _on_battle_finished 跑, 因此 snapshot
## 数据是子类 end() / _save_replay 之前的干净终态。
##
## 数据契约见 docs/view-logic-reconciliation.md。
signal battle_final_state_ready(final_state: Dictionary)


# ========== 字段 ==========

## 可选战斗日志。HexBattle 在 battle_finished 时从 procedure 镜像过来;
## 纯编辑态(skill_preview 等)和 headless 子类可保持 null。
## damage_utils / heal_action 等通过 `if battle.logger != null` 判空,
## 避免子类缺字段触发 "Invalid access" error。
var logger: HexBattleLogger = null


# ========== 初始化 ==========

func _init(id_value: String = "") -> void:
	super._init(id_value if id_value != "" else IdGenerator.generate("world"))
	type = "hex_world"
	# connect 在 super._init 之后, 子类 connect 之前 — 保证 base handler 先于子类 handler
	# 跑, snapshot 数据在 demo.end() / _save_replay / reset 之前抓取。
	battle_finished.connect(_emit_final_state_if_debug)


# ========== Grid ==========

## 接入 UGridMap autoload: configure 后把 autoload 的 model 同步到 self.grid。
func configure_grid(config: GridMapConfig) -> void:
	UGridMap.configure(config)
	grid = UGridMap.model
	grid_configured.emit(config)


# ========== Actor registry ==========

## 覆盖父类: 移除 Actor 时清理格子占用与预订。
## 框架层 remove_actor 不感知格子系统, 此处补充 hex 特化清理。
## 所有 HexBattleActor 子类 (CharacterActor / EnvironmentActor) 都走同一清理流程。
func remove_actor(actor_id: String) -> bool:
	var actor := super.get_actor(actor_id)
	if actor != null and actor is HexBattleActor:
		var battle_actor := actor as HexBattleActor
		if grid != null and battle_actor.hex_position != null and battle_actor.hex_position.is_valid():
			var occupant := grid.get_occupant(battle_actor.hex_position)
			if occupant == battle_actor:
				grid.remove_occupant(battle_actor.hex_position)
			for coord in _find_reservations_by(actor_id):
				grid.cancel_reservation(coord)
	return super.remove_actor(actor_id)


## 查找指定 actor 预订的所有格子。
func _find_reservations_by(actor_id: String) -> Array[HexCoord]:
	var result: Array[HexCoord] = []
	if grid == null:
		return result
	for coord in grid.get_all_coords():
		if grid.get_reservation(coord) == actor_id:
			result.append(coord)
	return result


## 覆盖父类, 返回类型收窄为 HexBattleActor。
## 公共战斗管线 (DamageUtils / event broadcast) 走此入口, 平权处理 character + environment。
func get_actor(actor_id: String) -> HexBattleActor:
	return super.get_actor(actor_id) as HexBattleActor


## 仅返回 character (env actor 转 cast 失败时返 null)。
## AI / 职业技能 / Heal / Buff 等 character-only 调用方使用此入口。
func get_character_actor(actor_id: String) -> CharacterActor:
	var actor := super.get_actor(actor_id)
	return actor as CharacterActor


func get_ability_set_for_actor(actor_id: String) -> BattleAbilitySet:
	var actor := get_actor(actor_id)
	if actor != null:
		return actor.ability_set
	return null


## 获取所有存活角色的 ID 列表 (用于 EventProcessor.process_post_event)。
## 隔离边界: 仅返回 character; environment 不响应 PostEvent 广播。
func get_alive_actor_ids() -> Array[String]:
	var result: Array[String] = []
	for actor in get_actors():
		if actor is CharacterActor and not (actor as CharacterActor).is_dead():
			result.append(actor.get_id())
	return result


## 获取所有存活角色对象 (供 AI strategy / scenario / scripting 使用)。
## 隔离边界: 仅返回 CharacterActor, 不含 environment。
func get_alive_actors() -> Array[CharacterActor]:
	var result: Array[CharacterActor] = []
	for actor in get_actors():
		if actor is CharacterActor and not (actor as CharacterActor).is_dead():
			result.append(actor as CharacterActor)
	return result


# ========== Final state snapshot (debug-only) ==========

## battle_finished handler: debug build 下抓 actor 终态发给 oracle。
## release 包零开销 (early return)。详见 battle_final_state_ready signal 注释。
func _emit_final_state_if_debug(_timeline: Dictionary) -> void:
	if not OS.has_feature("debug"):
		return
	battle_final_state_ready.emit(_build_final_state_snapshot())


## 拼装 final_state schema:
## {
##   "actors": {
##     "<actor_id>": {
##       "id":            String,
##       "type":          String,                  # "Character" / "Environment"
##       "is_dead":       bool,
##       "hex_position":  Dictionary,              # {q, r} or {} if invalid
##       "attribute":     Dictionary,              # 子类 get_attribute_snapshot 决定字段
##       "abilities":     Array[Dictionary],       # [{instance_id, config_id}, ...]
##       "tags":          Dictionary,              # tag_container snapshot
##     }
##   }
## }
##
## 死者也包含在内 (is_dead=true) — 死者的 buff/shield 仍挂在 ability_set 上, 对账时
## 仍要逐字段比 (位置例外, 见 reconciler 注释)。
func _build_final_state_snapshot() -> Dictionary:
	var actors_snapshot := {}
	for actor: Actor in get_actors():
		if actor is HexBattleActor:
			var battle_actor := actor as HexBattleActor
			actors_snapshot[battle_actor.get_id()] = _build_actor_snapshot(battle_actor)
	return { "actors": actors_snapshot }


func _build_actor_snapshot(actor: HexBattleActor) -> Dictionary:
	var pos: Dictionary = {}
	if actor.hex_position != null and actor.hex_position.is_valid():
		pos = actor.hex_position.to_dict()
	return {
		"id":           actor.get_id(),
		"type":         actor.type,
		"is_dead":      actor.is_dead(),
		"hex_position": pos,
		"attribute":    actor.get_attribute_snapshot(),
		"abilities":    actor.get_ability_snapshot(),
		"tags":         actor.get_tag_snapshot(),
	}


## 把 ProjectileSystem.tick 产生的投射物事件 (HIT/MISS) 广播给所有存活 actor
## 触发被动 handler。从 event_collector.collect() 只读快照,不 flush ——
## 剩余事件由 procedure 的 record_current_frame_events 统一写录像。
##
## 服务 BattleProcedure 子类(HexBattleProcedure / SkillPreviewProcedure)的 tick_once,
## 复用此方法避免各 procedure 各自内联 collect + match + process_post_event 同一段逻辑。
func broadcast_projectile_events() -> void:
	var events := GameWorld.event_collector.collect()
	if events.is_empty():
		return
	var alive_ids := get_alive_actor_ids()
	for event in events:
		var kind: String = event.get("kind", "")
		if kind == ProjectileEvents.PROJECTILE_HIT_EVENT or kind == ProjectileEvents.PROJECTILE_MISS_EVENT:
			GameWorld.event_processor.process_post_event(event, alive_ids, self)


## 判断 actor 能否对 target 使用 skill。
## 检查: 目标存活、目标种类白名单、阵营匹配(enemy/ally tag, 仅 character)、施法距离。
##
## target 类型放宽到 HexBattleActor: 默认 metadata `allowedTargetKinds = ["Character"]`
## 兜底 env 不会被现有技能误选; "打墙"等技能在 ability config 里显式 opt-in。
## 阵营/self 检查仅对 character target 有意义 (env 没有 team_id), 包在 type 分支里。
func can_use_skill_on(actor: CharacterActor, skill: Ability, target: HexBattleActor) -> bool:
	if target.is_dead():
		return false

	var allowed_kinds: Array = skill.metadata.get(
		HexBattleSkillMetaKeys.ALLOWED_TARGET_KINDS, ["Character"]
	)
	if not (target.type in allowed_kinds):
		return false

	if target is CharacterActor:
		var character_target := target as CharacterActor
		var same_team := actor.get_team_id() == character_target.get_team_id()
		var is_self := actor.get_id() == character_target.get_id()
		if skill.has_ability_tag("enemy") and same_team:
			return false
		if skill.has_ability_tag("ally") and not same_team:
			return false
		if skill.has_ability_tag("ally") and is_self and not skill.has_ability_tag("self"):
			return false

	var skill_range := skill.get_meta_int(HexBattleSkillMetaKeys.RANGE, 1)
	var distance := actor.hex_position.distance_to(target.hex_position)
	if distance > skill_range:
		return false

	return true
