## HexFacing - 角色逻辑朝向常量与 helper
##
## §0.3 V0: facing 是 CharacterActor 运行时状态 (实例字段)，不进 RawAttributeSet,
## 不放 HexBattleActor 基类 (EnvironmentActor 默认无 facing 语义)。
##
## V0 朝向规则:
## - 初始: A 队默认朝东 (DIR_EAST), B 队默认朝西 (DIR_WEST)
## - 主动移动: face toward destination
## - 主动攻击 / 施法: face toward target
## - forced displacement (push / knockback / pull): 不改变 facing
## - 被攻击 / Shadow Step 被瞬移者: 不自动转向
## - Shadow Step 落地: caster face target; target facing 不变
##
## 6 个方向对应 HexCoord.DIRECTIONS:
##   0 EAST, 1 NORTHEAST, 2 NORTHWEST, 3 WEST, 4 SOUTHWEST, 5 SOUTHEAST
class_name HexFacing


const DIR_EAST := 0
const DIR_NORTHEAST := 1
const DIR_NORTHWEST := 2
const DIR_WEST := 3
const DIR_SOUTHWEST := 4
const DIR_SOUTHEAST := 5

const REASON_INIT := "init"
const REASON_MOVE := "move"
const REASON_ACTIVE_USE := "active_use"
const REASON_SHADOW_STEP := "shadow_step"


## 反向: 同一轴线另一边
static func opposite(dir: int) -> int:
	return posmod(dir + 3, 6)


## 队伍默认朝向: A 队 (team 0) 朝东; B 队 (team 1) 朝西。
## 其它队伍 fallback 朝东。
static func default_for_team(team_id: int) -> int:
	if team_id == 1:
		return DIR_WEST
	return DIR_EAST


## 求 from → to 的方向 (0..5)。
##
## 优先用 cube 几何选最贴近的轴方向，避免 direction_to_neighbor 只对正好相邻
## 的 hex 有效。同位置返回 DIR_EAST 作为安全 fallback (调用方应避免本次 face)。
static func direction_between(from: HexCoord, to: HexCoord) -> int:
	if from == null or to == null:
		return DIR_EAST
	var dq := to.q - from.q
	var dr := to.r - from.r
	if dq == 0 and dr == 0:
		return DIR_EAST
	# cube: x=q, z=r, y=-q-r。对 6 个单位方向做 dot product,
	# 选夹角最小的方向；这能正确区分 EAST(1,0) 与 NORTHEAST(1,-1)。
	var scores: Array[int] = [
		2 * dq + dr,    # EAST  (1,-1,0)
		dq - dr,        # NE    (1,0,-1)
		-dq - 2 * dr,   # NW    (0,1,-1)
		-2 * dq - dr,   # WEST  (-1,1,0)
		-dq + dr,       # SW    (-1,0,1)
		dq + 2 * dr,    # SE    (0,-1,1)
	]
	var best_dir := DIR_EAST
	var best_score := scores[0]
	for i in range(1, scores.size()):
		if scores[i] > best_score:
			best_score = scores[i]
			best_dir = i
	return best_dir


## 主动技能 face-target action (PrimitiveAction)。任意 active skill 可以在
## on_timeline_start_actions 第一项放一个 `HexFacing.face_target_action()`，让
## caster 在 cast 起手转向 current target。reason 固定 "active_use"。
##
## phase 文档 §0.3 提示"集中入口"是 active-use execution 创建; 在不动 core 层
## ActiveUseComponent 的前提下, 由 skill 显式插入此 action 是最小入侵实现。
class _FaceTargetAction:
	extends Action.PrimitiveAction

	var _reason: String

	func _init(target_selector: TargetSelector, reason: String) -> void:
		super._init(target_selector)
		type = "face_target"
		_reason = reason

	func execute(ctx: ExecutionContext) -> ActionResult:
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		var caster_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		if battle == null or caster_id == "":
			return ActionResult.create_success_result([])
		var caster := battle.get_actor(caster_id)
		if not (caster is CharacterActor):
			return ActionResult.create_success_result([])
		var targets := get_targets(ctx)
		if targets.is_empty():
			return ActionResult.create_success_result([])
		var target_actor := battle.get_actor(targets[0])
		if target_actor == null or not target_actor.hex_position.is_valid():
			return ActionResult.create_success_result([])
		var events := HexFacing.face_actor_toward(
			caster as CharacterActor,
			target_actor.hex_position,
			_reason,
			ctx.event_collector
		)
		return ActionResult.create_success_result(events)


## 工厂: caster 转向 current target (event.target_actor_id) 的 PrimitiveAction。
static func face_target_action(reason: String = REASON_ACTIVE_USE) -> Action.PrimitiveAction:
	return _FaceTargetAction.new(HexBattleTargetSelectors.current_target(), reason)


## 唯一推荐的 setter: 同步更新 actor.facing_direction (source of truth) 并 push
## ActorFacingChangedEvent。逻辑读到的 facing 永远是最新值; 事件只作 audit / presentation。
##
## 当 new_dir 与 actor 当前一致, no-op 且返回空数组 (不重复发事件)。
## 返回新产生的 event_dict 列表 (caller append 进 ActionResult 即可)。
static func face_actor_toward(
	actor: CharacterActor,
	target_hex: HexCoord,
	reason: String,
	event_collector: EventCollector
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if actor == null or target_hex == null or not target_hex.is_valid():
		return events
	if not actor.hex_position.is_valid():
		return events
	var new_dir := direction_between(actor.hex_position, target_hex)
	var old_dir := actor.get_facing_direction()
	if new_dir == old_dir:
		return events
	actor.set_facing_direction(new_dir)
	var evt := BattleEvents.ActorFacingChangedEvent.create(
		actor.get_id(), old_dir, new_dir, reason
	)
	var pushed: Dictionary
	if event_collector != null:
		pushed = event_collector.push(evt.to_dict())
	else:
		pushed = evt.to_dict()
	events.append(pushed)
	return events
