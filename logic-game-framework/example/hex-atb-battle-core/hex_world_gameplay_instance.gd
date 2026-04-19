## HexWorldGameplayInstance - 六边形战斗世界 Instance
##
## 继承 WorldGameplayInstance, 承担六边形战斗系统的 actor registry / grid / systems 管理。
## 战斗推进由 HexBattleProcedure 承担 —— 参见 hex_battle_procedure.gd。
##
## 现有 HexBattle(example/hex-atb-battle/hex_battle.gd) 保留为 thin 兼容子类,
## 不破坏现有调用端 (SkillPreviewBattle / main.gd / SimulationManager 等)。
class_name HexWorldGameplayInstance
extends WorldGameplayInstance


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


# ========== Grid ==========

## 接入 UGridMap autoload: configure 后把 autoload 的 model 同步到 self.grid。
func configure_grid(config: GridMapConfig) -> void:
	UGridMap.configure(config)
	grid = UGridMap.model
	grid_configured.emit(config)


# ========== Actor registry ==========

## 覆盖父类: 移除 Actor 时清理格子占用与预订。
## 框架层 remove_actor 不感知格子系统, 此处补充 hex 特化清理。
func remove_actor(actor_id: String) -> bool:
	var actor := super.get_actor(actor_id)
	if actor != null and actor is CharacterActor:
		var char_actor := actor as CharacterActor
		if grid != null and char_actor.hex_position != null and char_actor.hex_position.is_valid():
			grid.remove_occupant(char_actor.hex_position)
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


## 覆盖父类, 返回类型收窄为 CharacterActor。
func get_actor(actor_id: String) -> CharacterActor:
	return super.get_actor(actor_id) as CharacterActor


func get_ability_set_for_actor(actor_id: String) -> BattleAbilitySet:
	var actor := get_actor(actor_id)
	if actor != null:
		return actor.ability_set
	return null


## 获取所有存活角色的 ID 列表(用于 EventProcessor.process_post_event)。
func get_alive_actor_ids() -> Array[String]:
	var result: Array[String] = []
	for actor in get_actors():
		if actor is CharacterActor and not (actor as CharacterActor).is_dead():
			result.append(actor.get_id())
	return result


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
## 检查: 目标存活、阵营匹配(enemy/ally tag)、施法距离。
func can_use_skill_on(actor: CharacterActor, skill: Ability, target: CharacterActor) -> bool:
	if target.is_dead():
		return false

	var same_team := actor.get_team_id() == target.get_team_id()
	if skill.has_ability_tag("enemy") and same_team:
		return false
	if skill.has_ability_tag("ally") and not same_team:
		return false

	if skill.has_ability_tag("ally") and actor.get_id() == target.get_id():
		return false

	var skill_range := skill.get_meta_int(HexBattleSkillMetaKeys.RANGE, 1)
	var distance := actor.hex_position.distance_to(target.hex_position)
	if distance > skill_range:
		return false

	return true
