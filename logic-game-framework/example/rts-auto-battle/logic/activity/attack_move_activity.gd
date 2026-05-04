## RtsAttackMoveActivity - 朝 target_pos 移动, 途中遇敌优先打 (P2.1 雏形, P2.4 完整)
##
## P2.1 实现:
##   - 默认: 持 child = MoveToActivity(target_pos), 跑完 child → activity DONE
##   - 提供 set_engagement_target(enemy_id): 调方探到敌人后调用,
##     activity 取消当前 child + push AttackActivity(enemy_id) 作新 child;
##     attack 完成 (target 死) 后 child 自然 DONE, tick 内重建 MoveTo child 续移动
##   - set_engagement_target("") 清除当前 attack 切回 move
##
## P2.1 不内置敌人扫描 — 由 controller / strategy 决定何时 set_engagement_target。
## P2.4 AutoTargetSystem 接入后, system 直接探目标 → 调 set_engagement_target。
##
## 决策来源: phase-2-core-systems.md P2.1 + P2.4 (AutoTargetSystem 联动)
class_name RtsAttackMoveActivity
extends RtsActivity


# ========== 常量 ==========

const ARRIVAL_THRESHOLD: float = 4.0


# ========== 字段 ==========

## 目标世界坐标 (像素); 路径终点。
var target_pos: Vector2

## M7d — 通过 bind_runtime 注入的 motion component(替代 nav_agent)。
var _motion: RtsMotionComponent = null

## 当前正在打的 enemy id (""=无, 走 MoveTo child)
var _engaging_target_id: String = ""


# ========== 初始化 ==========

func _init(p_target_pos: Vector2) -> void:
	target_pos = p_target_pos


func bind_runtime(motion_component: RtsMotionComponent) -> void:
	_motion = motion_component
	super.bind_runtime(motion_component)


# ========== 公共 API (调方在外部 push 引擎目标) ==========

## 调用方探到敌人后调用, AttackMove 切换为 attack child;
## 传 ""→ 取消当前 attack child, 恢复 move child。
##
## 同 enemy_id 重复调用是 no-op (避免抖动)。
func set_engagement_target(enemy_id: String) -> void:
	if enemy_id == _engaging_target_id:
		return
	_engaging_target_id = enemy_id
	if child_activity != null:
		child_activity.cancel()
		child_activity = null


# ========== 钩子 ==========

func on_first_run(_actor: RtsUnitActor, _world: RtsWorldGameplayInstance) -> void:
	_build_child_activity()


func tick(actor: RtsUnitActor, _world: RtsWorldGameplayInstance, _dt: float) -> bool:
	if actor == null or actor.is_dead():
		return false
	# 已 "靠近" target_pos → AttackMove DONE → strategy 接管 → AttackActivity 攻击 cache target.
	# 阈值按 movement_layer 分:
	#   - GROUND: attack_range × 1.05 (footprint 阻挡 melee 卡 ct 外缘 ~30px > ARRIVAL_THRESHOLD,
	#     用 attack_range 判 = 与 AttackActivity in-range 同阈值,无缝接管)
	#   - AIR: ARRIVAL_THRESHOLD (飞行能穿 footprint 直达 ct 中心; 用 attack_range early-done 会
	#     让 scout 站桩在 ct 外某点, 经常恰在防御塔射程边缘外 → 防御塔 0 hits 漏击)
	# engaging_target_id 非空 (已切 attack 状态) 不走 early-done, attack child 自己跑.
	if _engaging_target_id == "" and actor.attribute_set != null:
		var threshold_sq: float
		if actor.movement_layer == MovementLayer.Layer.AIR:
			threshold_sq = ARRIVAL_THRESHOLD * ARRIVAL_THRESHOLD
		else:
			var atk_with_tol: float = actor.attribute_set.attack_range * 1.05
			threshold_sq = atk_with_tol * atk_with_tol
		if actor.position_2d.distance_squared_to(target_pos) <= threshold_sq:
			return false
	# child 缺失 (上一 child DONE 或被 cancel 后置 null) → 重建
	if child_activity == null:
		_build_child_activity()
	# child DONE → 主任务也结束 (move 已抵达, 或 attack 目标死后没新目标)
	if child_activity != null and child_activity.is_done():
		# attack 完成后默认回到 move; engagement 在 attack 内 cleanup
		if _engaging_target_id != "":
			_engaging_target_id = ""
			child_activity = null
			_build_child_activity()
			return true
		return false
	return true


func on_last_run(_actor: RtsUnitActor, _world: RtsWorldGameplayInstance) -> void:
	if _motion != null:
		_motion.motion.stop()


func is_equivalent_to(other: RtsActivity) -> bool:
	if not (other is RtsAttackMoveActivity):
		return false
	var other_am := other as RtsAttackMoveActivity
	return target_pos.distance_squared_to(other_am.target_pos) < 1.0


func get_intent_label() -> String:
	if _engaging_target_id != "":
		return "attack"
	return "attack_move"


# ========== 内部 ==========

func _build_child_activity() -> void:
	var built: RtsActivity
	if _engaging_target_id != "":
		built = RtsAttackActivity.new(_engaging_target_id)
	else:
		# canonicalize=false: AttackMove target_pos 通常是 enemy_ct 中心 (落 building footprint
		# impassable 区), canonicalize=true 会把 goal mutate 到 ct 外缘 navcell, unit 永远走不到
		# ARRIVAL_THRESHOLD 内 → MoveTo 不 done → AttackMove 不 done → strategy 不接管. 用
		# canonicalize=false 走 LongPath direct-path fallback, unit 走到 ct 中心附近 ARRIVAL=4 →
		# MoveTo done → AttackMove done → strategy 接管 RtsAttackActivity 攻 ct.
		built = RtsMoveToActivity.new(target_pos, false)
	child_activity = built
	if _motion != null:
		child_activity.bind_runtime(_motion)
