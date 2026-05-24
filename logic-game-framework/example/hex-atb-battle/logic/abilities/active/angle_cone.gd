## Angle Cone · 基于真实世界角度的锥形 AoE
##
## V1 行为 (per advanced-skills-next-batch.md Phase D):
## - 释放方式: target_coord (不点 actor)
## - forward = coord_to_world(target_coord) - coord_to_world(caster.hex_position)
## - 命中条件 (per candidate, world coords):
##     hex_distance(candidate, caster) <= CONE_RANGE (hex 距离做粗筛, 避免遍历整张地图)
##     |angle(forward, candidate_vec)| <= HALF_ANGLE_DEG + EPSILON
## - target_coord == caster 是 caller contract 错误 → Log.assert_crash
## - 命中过滤: 敌方 alive CharacterActor
## - 命中顺序确定: hex_distance 升序 → world angle 升序 → coord sort_key 升序
## - damage = caster.atk PHYSICAL
##
## 与 GridCone 区别:
##   - GridCone 量化到 6 方向 sector, 锥宽 ≈ 60° 三 hex slice
##   - AngleCone 真实角度 45° 半角, 锥宽 90° 但比 GridCone 三 hex slice 通常更窄
##   - 同站位下 GridCone 通常多命中至少 1 个目标 (corner 上 grid 内 / angle 外的)
class_name HexBattleAngleCone


const CONFIG_ID := "skill_angle_cone"
const TIMELINE_ID := "skill_angle_cone"
const COOLDOWN_MS := 8000.0
const CONE_RANGE := 3
const HALF_ANGLE_DEG := 45.0
const HALF_ANGLE_RAD := deg_to_rad(HALF_ANGLE_DEG)
## 浮点 epsilon: 让边界目标不抖动 (45° 边上的目标稳定命中或稳定不命中, 取决于 grid 几何).
const ANGLE_EPSILON_RAD := 0.001


static var ANGLE_CONE_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	500.0,
	{
		TimelineTags.HIT: 300.0,
		TimelineTags.END: 500.0,
	}
)


static var _CASTER_ATK_DAMAGE: FloatResolver = Resolvers.float_fn(func(ctx: ExecutionContext) -> float:
	var owner_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	if owner_id == "":
		return 0.0
	var actor := GameWorld.get_actor(owner_id)
	if actor == null or not (actor is CharacterActor):
		return 0.0
	return (actor as CharacterActor).attribute_set.atk
)


## Phase E · debug 检查区域几何 (selector 与 StageCue.params overlay 共用).
## 同 GridCone.compute_checked_coords 语义: 返回 selector 会枚举的全部格子, 不做 actor 占位过滤.
static func compute_checked_coords(caster_pos: HexCoord, target_coord: HexCoord) -> Array[Dictionary]:
	var coords: Array[Dictionary] = []
	if caster_pos == null or target_coord == null or caster_pos.equals(target_coord):
		return coords
	var caster_world: Vector2 = UGridMap.model.coord_to_world(caster_pos)
	var target_world: Vector2 = UGridMap.model.coord_to_world(target_coord)
	var forward: Vector2 = target_world - caster_world
	if forward.length_squared() == 0.0:
		return coords
	for cand in UGridMap.model.get_range(caster_pos, HexBattleAngleCone.CONE_RANGE):
		if cand.equals(caster_pos):
			continue
		var cand_world: Vector2 = UGridMap.model.coord_to_world(cand)
		var cand_vec: Vector2 = cand_world - caster_world
		if cand_vec.length_squared() == 0.0:
			continue
		var angle: float = absf(forward.angle_to(cand_vec))
		if angle > HexBattleAngleCone.HALF_ANGLE_RAD + HexBattleAngleCone.ANGLE_EPSILON_RAD:
			continue
		coords.append({"q": cand.q, "r": cand.r})
	return coords


static var _DEBUG_PARAMS_RESOLVER: DictResolver = Resolvers.dict_fn(func(ctx: ExecutionContext) -> Dictionary:
	var event := ctx.get_current_event()
	var target_coord_dict: Dictionary = event.get("target_coord", {}) as Dictionary
	if not (target_coord_dict.has("q") and target_coord_dict.has("r")):
		return {}
	var owner_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	if owner_id.is_empty():
		return {}
	var actor := GameWorld.get_actor(owner_id)
	if actor == null or not (actor is CharacterActor):
		return {}
	var caster_pos: HexCoord = (actor as CharacterActor).hex_position
	var target_coord := HexCoord.from_dict(target_coord_dict)
	if caster_pos.equals(target_coord):
		return {}
	return {
		"shape": "angle_cone",
		"origin_coord": {"q": caster_pos.q, "r": caster_pos.r},
		"target_coord": {"q": target_coord.q, "r": target_coord.r},
		"checked_coords": HexBattleAngleCone.compute_checked_coords(caster_pos, target_coord),
		"range": HexBattleAngleCone.CONE_RANGE,
		"half_angle_deg": HexBattleAngleCone.HALF_ANGLE_DEG,
	}
)


class _AngleConeSelector:
	extends TargetSelector

	func select(ctx: ExecutionContext) -> Array[String]:
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		if battle == null:
			return []
		var caster_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		if caster_id.is_empty():
			return []
		var caster := battle.get_actor(caster_id) as CharacterActor
		if caster == null:
			return []
		var caster_pos: HexCoord = caster.hex_position
		var event := ctx.get_current_event()
		var target_coord_dict: Dictionary = event.get("target_coord", {}) as Dictionary
		Log.assert_crash(target_coord_dict.has("q") and target_coord_dict.has("r"),
			"HexBattleAngleCone._AngleConeSelector",
			"activate event missing target_coord.q/r; AI/UI must populate target_coord for cone skills")
		var target_coord := HexCoord.from_dict(target_coord_dict)
		Log.assert_crash(not target_coord.equals(caster_pos),
			"HexBattleAngleCone._AngleConeSelector",
			"target_coord (%d,%d) == caster.hex_position; AI/UI must enforce distinct pos" % [target_coord.q, target_coord.r])

		var caster_world: Vector2 = UGridMap.model.coord_to_world(caster_pos)
		var target_world: Vector2 = UGridMap.model.coord_to_world(target_coord)
		var forward: Vector2 = target_world - caster_world
		Log.assert_crash(forward.length_squared() > 0.0,
			"HexBattleAngleCone._AngleConeSelector",
			"forward vector zero; coord_to_world should never produce coincident points for distinct coords")

		var candidates := UGridMap.model.get_range(caster_pos, HexBattleAngleCone.CONE_RANGE)
		var caster_team := caster.get_team_id()
		var hits: Array[Dictionary] = []
		for cand in candidates:
			if cand.equals(caster_pos):
				continue
			var occupant = battle.grid.get_occupant(cand)
			if occupant == null:
				continue
			if not (occupant is CharacterActor):
				continue
			var c := occupant as CharacterActor
			if c.is_dead():
				continue
			if c.get_team_id() == caster_team:
				continue
			var cand_world: Vector2 = UGridMap.model.coord_to_world(cand)
			var cand_vec: Vector2 = cand_world - caster_world
			if cand_vec.length_squared() == 0.0:
				continue
			var angle: float = absf(forward.angle_to(cand_vec))
			if angle > HexBattleAngleCone.HALF_ANGLE_RAD + HexBattleAngleCone.ANGLE_EPSILON_RAD:
				continue
			hits.append({
				"actor_id": c.get_id(),
				"distance": caster_pos.distance_to(cand),
				"angle": angle,
				"sort_key": cand.q * 1000 + cand.r,
			})

		hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["distance"] != b["distance"]:
				return a["distance"] < b["distance"]
			if absf((a["angle"] as float) - (b["angle"] as float)) > 0.0001:
				return (a["angle"] as float) < (b["angle"] as float)
			return a["sort_key"] < b["sort_key"]
		)
		var result: Array[String] = []
		for h in hits:
			result.append(h["actor_id"] as String)
		return result


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("角度锥击")
	.description("以 caster 为顶点, 朝目标方向 半角 %d° 锥形, 范围 %d 格, 命中所有敌方 (atk 物理)" % [int(HALF_ANGLE_DEG), CONE_RANGE])
	.ability_tags(["skill", "active", "melee", "enemy", "cone", "aoe"])
	.meta(HexBattleSkillMetaKeys.RANGE, CONE_RANGE)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.ability_owner(),
			Resolvers.str_val("angle_cone_cast"),
			_DEBUG_PARAMS_RESOLVER,
		)])
		.on_tag(TimelineTags.HIT, [
			HexBattleDamageAction.new(
				_AngleConeSelector.new(),
				_CASTER_ATK_DAMAGE,
				BattleEvents.DamageType.PHYSICAL,
			)
		])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(Condition.NoTagCondition.new(HexBattleSilenceBuff.TAG_CANT_USE_SKILL))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build()
	)
	.build()
)
