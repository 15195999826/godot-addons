## Grid Cone · 基于 hex 格子固定角度 footprint 的锥形 AoE
##
## 行为:
## - 释放方式: target_coord (不点 actor; 玩家点格子)
## - cast_dir = HexFacing.direction_between(caster, target_coord)
## - target_coord 是 cone origin; range=3 包含 origin, 共 3 层固定中心锥形 footprint
## - target_coord == caster.hex_position 时, cast_dir 使用 caster 当前 facing
## - target_coord 字段必须存在 (event["target_coord"].has(q,r)); 缺字段是 caller contract 错误
##   → Log.assert_crash
## - 命中过滤: 敌方 alive CharacterActor 占该格
## - 命中顺序确定: distance_to(cone_origin) 升序 → coord (q*1000+r) 升序 二级
##   (multiplier 需 > 地图半径 diameter)
## - damage = caster.atk PHYSICAL (复用 HexBattleDamageAction)
##
## 【AOE 几何 = 每技能各写一套, cone/line 几何模板】(angle_cone / piercing_line 同类):
##   三者各自实现 footprint 几何 (grid_cone 走 HexCoord.DIRECTIONS sector; angle_cone 走
##   world-space angle; piercing_line 走 neighbor walk) + 各自复制"算 footprint → 过滤存活
##   敌方占格"的 occupant/team/dead 过滤尾巴。曾评估抽 HexBattleAreaGeometry (cone/line/ring
##   → Array[HexCoord]) + HexBattleAreaSelector (吃 footprint-resolver + origin 统一过滤),
##   但每个 cone 还各有 ~100 行真正不同的几何, 抽象收益有限且本框架=技能展示沙盒, 故【暂不抽】,
##   留待未来新增第 4 个 AOE 技能时一并做。RANGE 语义: footprint 从 caster_pos 发出 (此处
##   target_coord 仅定方向), 最远 == CONE_RANGE == 声明 RANGE, 与 angle_cone 一致。
class_name HexBattleGridCone


const CONFIG_ID := "skill_grid_cone"
const COOLDOWN_MS := 8000.0
const CONE_RANGE := 3


static var _CASTER_ATK_DAMAGE: FloatResolver = HexBattleSkillHelpers.caster_atk_damage()


## Phase E · debug 检查区域几何 (selector 与 StageCue.params overlay 共用).
##
## 返回所有"selector 会枚举到"的格子 (包含 cone origin, 不论格内是否有敌人).
## checked_coords = 完整 fixed footprint 区域; targetActorIds = 真正命中的 actor —— 二者
## 区别让 frontend overlay 可显示"扫过区域"vs"命中目标"双层 cue.
static func compute_checked_coords(
	caster_pos: HexCoord,
	target_coord: HexCoord,
	caster_facing_direction: int = HexFacing.DIR_EAST
) -> Array[Dictionary]:
	if caster_pos == null or target_coord == null:
		return []
	var cast_dir := _resolve_cast_direction(caster_pos, target_coord, caster_facing_direction)
	return compute_grid_cone_from_origin(target_coord, cast_dir, HexBattleGridCone.CONE_RANGE)


## 从 cone origin 出发, 按指定方向计算 grid cone footprint。
## origin 自身是第 1 层, 也属于 checked area。
##
## range=3 时 checked area 为 1+3+5=9 格。cast_dir 是中心线, 两侧边界
## 固定取相邻方向, 从而得到 grid-locked footprint；动态角度锥形由 angle_cone 处理。
static func compute_grid_cone_from_origin(
	origin_coord: HexCoord,
	cast_dir: int,
	cone_range: int
) -> Array[Dictionary]:
	var coords: Array[Dictionary] = []
	if origin_coord == null or cone_range <= 0:
		return coords
	var center_dir := posmod(cast_dir, 6)
	var left_row_dir := posmod(center_dir + 2, 6)
	var right_row_dir := posmod(center_dir - 2, 6)
	for distance in range(cone_range):
		var row_center := _offset_coord(origin_coord, center_dir, distance)
		coords.append({"q": row_center.q, "r": row_center.r})
		for lateral_steps in range(1, distance + 1):
			var left_cand := _offset_coord(row_center, left_row_dir, lateral_steps)
			coords.append({"q": left_cand.q, "r": left_cand.r})
			var right_cand := _offset_coord(row_center, right_row_dir, lateral_steps)
			coords.append({"q": right_cand.q, "r": right_cand.r})
	return coords


static func _resolve_cast_direction(
	caster_pos: HexCoord,
	target_coord: HexCoord,
	caster_facing_direction: int
) -> int:
	if caster_pos.equals(target_coord):
		return posmod(caster_facing_direction, 6)
	return HexFacing.direction_between(caster_pos, target_coord)


static func _direction_edges(cast_dir: int) -> Array[int]:
	return [
		posmod(cast_dir + 1, 6),
		posmod(cast_dir - 1, 6),
	]


static func _offset_coord(
	origin_coord: HexCoord,
	direction: int,
	steps: int
) -> HexCoord:
	var dir_vec := HexCoord.DIRECTIONS[posmod(direction, 6)]
	return HexCoord.new(
		origin_coord.q + dir_vec.x * steps,
		origin_coord.r + dir_vec.y * steps
	)


## DictResolver 在 on_timeline_start 解析: 返回 frontend overlay 需要的几何 payload.
## payload 字段: shape / origin_coord / target_coord / checked_coords / range /
## caster_coord / cast_direction / direction_edges.
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
	var caster := actor as CharacterActor
	var caster_pos: HexCoord = caster.hex_position
	var target_coord := HexCoord.from_dict(target_coord_dict)
	var cast_dir := HexBattleGridCone._resolve_cast_direction(
		caster_pos,
		target_coord,
		caster.get_facing_direction()
	)
	return {
		"shape": "grid_cone",
		"origin_coord": {"q": target_coord.q, "r": target_coord.r},
		"caster_coord": {"q": caster_pos.q, "r": caster_pos.r},
		"target_coord": {"q": target_coord.q, "r": target_coord.r},
		"checked_coords": HexBattleGridCone.compute_checked_coords(
			caster_pos,
			target_coord,
			caster.get_facing_direction()
		),
		"range": HexBattleGridCone.CONE_RANGE,
		"cast_direction": cast_dir,
		"direction_edges": HexBattleGridCone._direction_edges(cast_dir),
	}
)


## TargetSelector 子类: target_coord 为 origin, 命中 fixed grid cone footprint 内
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
		var cast_dir := HexBattleGridCone._resolve_cast_direction(
			caster_pos,
			target_coord,
			caster.get_facing_direction()
		)
		var checked_coords := HexBattleGridCone.compute_grid_cone_from_origin(
			target_coord,
			cast_dir,
			HexBattleGridCone.CONE_RANGE
		)
		var caster_team := caster.get_team_id()
		var hits: Array[Dictionary] = []
		for coord_dict in checked_coords:
			var cand := HexCoord.from_dict(coord_dict)
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
				"distance": target_coord.distance_to(cand),
				"sort_key": cand.q * 1000 + cand.r,
			})

		# 命中顺序确定: cone origin distance 升序 → sort_key 升序
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
	.description("以目标格为锥形起点, 沿 caster→目标格方向展开 3 层固定格子锥形, 命中所有敌方 (atk 物理)")
	.ability_tags(["skill", "active", "melee", "enemy", "cone", "aoe"])
	.meta(HexBattleSkillMetaKeys.RANGE, CONE_RANGE)
	.meta(HexBattleSkillMetaKeys.TARGETING, HexBattleSkillMetaKeys.TARGETING_COORD)
	.active_use(
		HexBattleCooldownSystem.apply_standard_active_gating(ActiveUseConfig.builder(), COOLDOWN_MS)
		.timeline(HexBattleStdTimelines.MELEE_500)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.ability_owner(),
			Resolvers.str_val(HexBattleCues.GRID_CONE_CAST),
			_DEBUG_PARAMS_RESOLVER,
		)])
		.on_tag(TimelineTags.HIT, [
			HexBattleDamageAction.new(
				_GridConeSelector.new(),
				_CASTER_ATK_DAMAGE,
				BattleEvents.DamageType.PHYSICAL,
			)
		])
		.build()
	)
	.build()
)
