## Piercing Line #G - 沿 caster→target 方向直线穿透
##
## V1 行为:
## - direction: caster.hex_position → target.hex_position 的单位方向
## - length: 3 hex
## - filter: 敌方 alive CharacterActor (沿线遍历, 每格找 occupant)
## - damage: 复用 HexBattleDamageAction (= atk PHYSICAL)
## - 同 tick 命中目标集合稳定; hit order = 沿方向 从 caster 起依次
##
## 实现: 内嵌 _PiercingLineSelector (TargetSelector 子类) 在 select() 中:
## 1. caster.hex_position 已知; current_event.target_actor_id 拿到 selected target → target_pos
## 2. direction = first_neighbor_to(target_pos) (HexCoord.direction_to_neighbor)
## 3. 沿 direction 遍历 length 步, 每步看 grid.get_occupant(coord), 是敌方 alive CharacterActor 加入 target list
## 4. 不阻挡: 当前 V1 不考虑 wall / blocker; 沿线所有敌方都命中
class_name HexBattlePiercingLine


const CONFIG_ID := "skill_piercing_line"
const COOLDOWN_MS := 8000.0
const LINE_LENGTH := 3


static var _CASTER_ATK_DAMAGE: FloatResolver = HexBattleSkillHelpers.caster_atk_damage()


## TargetSelector 子类: 沿 caster→event.target 方向遍历 LINE_LENGTH 格,
## 选出占格的敌方 alive CharacterActor。
class _PiercingLineSelector:
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
		var event := ctx.get_current_event()
		var target_id := str(event.get("target_actor_id", ""))
		if target_id.is_empty():
			return []
		var target := battle.get_actor(target_id) as HexBattleActor
		if target == null:
			return []
		var caster_pos: HexCoord = caster.hex_position
		# anchor 寻址语义 (known / intentional, 非 fizzle):
		# anchor 若在 cast→HIT(300ms) 间死亡, 仍留在 world registry 且 hex_position 字段
		# 保留 (死亡只清 grid occupant, 见 hex_battle_damage_utils._clear_grid_footprint),
		# 故这里照常用其最后位置定方向 —— 整条线不会因 anchor 死亡而消失。沿线 footprint
		# 遍历另有 c.is_dead() 跳过, 所以不会结算到尸体本身。
		var target_pos: HexCoord = target.hex_position
		if caster_pos == null or target_pos == null:
			return []
		# 方向: 先找 caster 邻格能到 target 方向的 neighbor index
		# 注意: target 可能在 caster 邻格外 (range=3), 先求 caster→target 方向。
		# 简单方案: 遍历 6 个方向找 caster.neighbor(dir) 最靠近 target 的 (distance 最短)。
		var best_dir := -1
		var best_dist := 9999
		for dir in range(6):
			var step: HexCoord = caster_pos.neighbor(dir)
			var d := step.distance_to(target_pos)
			if d < best_dist:
				best_dist = d
				best_dir = dir
		if best_dir < 0:
			return []

		# 沿 best_dir 走 LINE_LENGTH 步, 每步检查 grid.occupant, 加敌方 alive CharacterActor
		var result: Array[String] = []
		var caster_team := caster.get_team_id()
		var cur: HexCoord = caster_pos
		for step_idx in range(HexBattlePiercingLine.LINE_LENGTH):
			cur = cur.neighbor(best_dir)
			if not battle.grid.has_tile(cur):
				break
			var occupant = battle.grid.get_occupant(cur)
			if occupant == null:
				continue
			if not (occupant is CharacterActor):
				continue
			var c := occupant as CharacterActor
			if c.is_dead():
				continue
			if c.get_team_id() == caster_team:
				continue
			result.append(c.get_id())
		return result


static var ABILITY := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("穿透箭")
	.description("沿目标方向直线穿透 %d 格, 命中所有敌方角色 (atk 物理)" % LINE_LENGTH)
	.ability_tags(["skill", "active", "ranged", "enemy", "line", "aoe"])
	.meta(HexBattleSkillMetaKeys.RANGE, LINE_LENGTH)
	.meta(HexBattleSkillMetaKeys.TARGETING, HexBattleSkillMetaKeys.TARGETING_ACTOR)
	.active_use(
		HexBattleCooldownSystem.apply_standard_active_gating(ActiveUseConfig.builder(), COOLDOWN_MS)
		.timeline(HexBattleStdTimelines.MELEE_500)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val(HexBattleCues.PIERCING_LINE_CAST),
		)])
		.on_tag(TimelineTags.HIT, [
			HexBattleDamageAction.new(
				_PiercingLineSelector.new(),
				_CASTER_ATK_DAMAGE,
				BattleEvents.DamageType.PHYSICAL,
			)
		])
		.build()
	)
	.build()
)
