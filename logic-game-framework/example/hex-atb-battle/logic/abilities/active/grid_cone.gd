## Grid Cone · 基于 hex 格子方向 sector 的扇形 AoE
##
## V1 行为 (per advanced-skills-next-batch.md Phase D):
## - 释放方式: target_coord (不点 actor; 玩家点格子)
## - cast_dir = HexFacing.direction_between(caster, target_coord)
## - 选区: caster range 内所有 candidate hex; direction_between(caster→candidate)
##   必须落在 {cast_dir-1, cast_dir, cast_dir+1} 三方向 sector 才算前向命中
## - target_coord 字段必须存在 (event["target_coord"].has(q,r)); 缺字段 / target_coord == caster
##   都是 caller contract 错误 → Log.assert_crash (不 fallback 到 facing)
## - 命中过滤: 敌方 alive CharacterActor 占该格
## - 命中顺序确定: distance_to(caster) 升序 → coord (q*1000+r) 升序 二级 (multiplier 需 > 地图半径 diameter)
## - damage = caster.atk PHYSICAL (复用 HexBattleDamageAction)
class_name HexBattleGridCone


const CONFIG_ID := "skill_grid_cone"
const TIMELINE_ID := "skill_grid_cone"
const COOLDOWN_MS := 8000.0
const CONE_RANGE := 3


static var GRID_CONE_TIMELINE := TimelineData.new(
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
##
## 返回所有"selector 会枚举到"的格子 (不含 caster 自身, 不论格内是否有敌人).
## checked_coords = 完整 sector 区域; targetActorIds = 真正命中的 actor —— 二者
## 区别让 frontend overlay 可显示"扫过区域"vs"命中目标"双层 cue.
##
## caster_pos.equals(target_coord) 在此 helper 返回空; 真正 cast 路径上 selector 自身
## 仍会 Log.assert_crash, 这层只为 visualizer 提前查询时不崩溃.
static func compute_checked_coords(caster_pos: HexCoord, target_coord: HexCoord) -> Array[Dictionary]:
	var coords: Array[Dictionary] = []
	if caster_pos == null or target_coord == null or caster_pos.equals(target_coord):
		return coords
	var cast_dir := HexFacing.direction_between(caster_pos, target_coord)
	var sector: Array[int] = [
		posmod(cast_dir - 1, 6),
		cast_dir,
		posmod(cast_dir + 1, 6),
	]
	for cand in UGridMap.model.get_range(caster_pos, HexBattleGridCone.CONE_RANGE):
		if cand.equals(caster_pos):
			continue
		var cand_dir := HexFacing.direction_between(caster_pos, cand)
		if not sector.has(cand_dir):
			continue
		coords.append({"q": cand.q, "r": cand.r})
	return coords


## DictResolver 在 on_timeline_start 解析: 返回 frontend overlay 需要的几何 payload.
## payload 字段: shape / origin_coord / target_coord / checked_coords / range /
## cast_direction / direction_sector.
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
	var cast_dir := HexFacing.direction_between(caster_pos, target_coord)
	return {
		"shape": "grid_cone",
		"origin_coord": {"q": caster_pos.q, "r": caster_pos.r},
		"target_coord": {"q": target_coord.q, "r": target_coord.r},
		"checked_coords": HexBattleGridCone.compute_checked_coords(caster_pos, target_coord),
		"range": HexBattleGridCone.CONE_RANGE,
		"cast_direction": cast_dir,
		"direction_sector": [
			posmod(cast_dir - 1, 6),
			cast_dir,
			posmod(cast_dir + 1, 6),
		],
	}
)


## TargetSelector 子类: caster range 内, 方向 ∈ {cast_dir-1, cast_dir, cast_dir+1} sector
## 的敌方 alive CharacterActor。
class _GridConeSelector:
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
		# Caller contract: activate event 必须显式 set target_coord; 缺字段会让 HexCoord.from_dict({})
		# 静默返回 (0,0) 误用作 cast 方向 → silent gameplay corruption. fail fast.
		Log.assert_crash(target_coord_dict.has("q") and target_coord_dict.has("r"),
			"HexBattleGridCone._GridConeSelector",
			"activate event missing target_coord.q/r; AI/UI must populate target_coord for cone skills")
		var target_coord := HexCoord.from_dict(target_coord_dict)
		# Caller contract: target_coord != caster.hex_position; AI / UI 必须避免传入 own pos.
		Log.assert_crash(not target_coord.equals(caster_pos),
			"HexBattleGridCone._GridConeSelector",
			"target_coord (%d,%d) == caster.hex_position; AI/UI must enforce distinct pos" % [target_coord.q, target_coord.r])

		var cast_dir := HexFacing.direction_between(caster_pos, target_coord)
		var sector: Array[int] = [
			posmod(cast_dir - 1, 6),
			cast_dir,
			posmod(cast_dir + 1, 6),
		]

		var candidates := UGridMap.model.get_range(caster_pos, HexBattleGridCone.CONE_RANGE)
		var caster_team := caster.get_team_id()
		var hits: Array[Dictionary] = []
		for cand in candidates:
			if cand.equals(caster_pos):
				continue
			var cand_dir := HexFacing.direction_between(caster_pos, cand)
			if not sector.has(cand_dir):
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
			hits.append({
				"actor_id": c.get_id(),
				"distance": caster_pos.distance_to(cand),
				"sort_key": cand.q * 1000 + cand.r,
			})

		# 命中顺序确定: distance 升序 → sort_key 升序
		hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["distance"] != b["distance"]:
				return a["distance"] < b["distance"]
			return a["sort_key"] < b["sort_key"]
		)
		var result: Array[String] = []
		for h in hits:
			result.append(h["actor_id"] as String)
		return result


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("格栅锥击")
	.description("以 caster 当前格为中心, 沿目标方向 3 格扇形 (含 ±1 方向) 命中所有敌方 (atk 物理)")
	.ability_tags(["skill", "active", "melee", "enemy", "cone", "aoe"])
	.meta(HexBattleSkillMetaKeys.RANGE, CONE_RANGE)
	.active_use(
		ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.ability_owner(),
			Resolvers.str_val("grid_cone_cast"),
			_DEBUG_PARAMS_RESOLVER,
		)])
		.on_tag(TimelineTags.HIT, [
			HexBattleDamageAction.new(
				_GridConeSelector.new(),
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
