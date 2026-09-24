extends Node

## VisualDirector（表演实例骨架）的 pump 顺序合同与 live 入口钉子
##
## 钉住合同：
## - 四件在 _init 建好：不入树也能 pump / 读账本
## - pump：事件直改先落账本（同趟里 actor_spawned 事件之后的卡片翻译已能读到新 actor 的位置）→ 翻译入步进器 →
##   推账本时间 → 步进 → 记账（活跃 + 本趟完成）→ 到期清理 + hp 追赶 → flush；没有事件也照样推动画
## - 7 条信号 1:1 转发自账本（actor 4 条 + effect 3 条）
## - live 入口（子类经 _state / _stepper 直达）：seed_actor 入账并广播 actor_spawned + actor_state_changed，
##   hp 缺省 = max_hp、max_hp 缺省 1，同 id 重复 seed 忽略；despawn_actor 出账并广播 actor_despawned，未知 id 忽略；
##   cancel_for_actor 只撤该 actor 的在飞卡片、不补发完成、在飞插值停在撤销那一刻；has_actor_action 随入队 / 完成 /
##   撤销翻转；set_actor_position 直接定位（账本 + 在飞插值一起写，当场广播）


## 探针翻译员：probe_move 从账本当前位置线性移到 to；probe_hit 出 hp delta + 飘字 + 攻击特效三张卡片
class ProbeTranslator extends Translator:
	const PROBE_MOVE := "probe_move"
	const PROBE_HIT := "probe_hit"

	func _init() -> void:
		translator_name = "ProbeTranslator"

	func can_handle(event: Dictionary) -> bool:
		var kind := get_event_kind(event)
		return kind == PROBE_MOVE or kind == PROBE_HIT

	func translate(event: Dictionary, query: VisualStateQuery) -> Array[VisualAction]:
		var actor_id := get_string_field(event, "actor_id")
		var out: Array[VisualAction] = []
		if get_event_kind(event) == PROBE_MOVE:
			var to: Array = event.get("to", [0, 0])
			out.append(VisualMoveAction.new(
				actor_id, query.get_actor_position(actor_id), Vector2(float(to[0]), float(to[1])),
				get_float_field(event, "duration", 200.0), VisualAction.EasingType.LINEAR))
		else:
			var amount := get_float_field(event, "amount", 10.0)
			var position := query.get_actor_position(actor_id)
			out.append(VisualHpDeltaAction.new(actor_id, -amount))
			out.append(VisualFloatingTextAction.new(
				actor_id, str(int(amount)), Color.RED, position, VisualFloatingTextAction.FloatingTextStyle.NORMAL, 500.0))
			out.append(VisualAttackVfxAction.new(
				"attacker", actor_id, position, position, get_float_field(event, "vfx_duration", 200.0)))
		return out


## 不带帧时钟的最小 live 子类：live 入口经 _state / _stepper 直达，事件由调用方攒好交给 pump
class LiveProbeDirector extends VisualDirector:
	func _init() -> void:
		super._init(TranslatorRegistry.new().register(ProbeTranslator.new()))

	func seed_probe(actor_id: String, position: Vector2, hp: float = NAN, max_hp: float = NAN) -> ActorVisualState:
		return _state.seed_actor(actor_id, actor_id, position, hp, max_hp)

	func despawn(actor_id: String) -> void:
		_stepper.cancel_for_actor(actor_id)
		_state.despawn_actor(actor_id)

	func cancel(actor_id: String) -> void:
		_stepper.cancel_for_actor(actor_id)

	func snap(actor_id: String, position: Vector2) -> void:
		_stepper.cancel_for_actor(actor_id)
		_state.set_actor_position(actor_id, position)

	func is_moving(actor_id: String) -> bool:
		return _stepper.has_actor_action(actor_id)


const NO_EVENTS: Array[Dictionary] = []


func _init() -> void:
	TestFramework.register_test("VisualDirector seed_actor 入账广播，pump 两条 move 到完成，has_actor_action 翻转", _test_seed_and_move)
	TestFramework.register_test("VisualDirector pump 事件直改先于翻译：同趟 spawn 后的 move 从新 actor 位置出发", _test_lifecycle_before_translate)
	TestFramework.register_test("VisualDirector cancel_for_actor 只撤该 actor 不补发完成，set_actor_position 直接定位", _test_cancel_and_snap)
	TestFramework.register_test("VisualDirector despawn_actor 出账广播，未知 id 忽略，同 id 可重新 seed", _test_despawn)
	TestFramework.register_test("VisualDirector 转发账本 7 条信号：hp delta 死亡、飘字 / 攻击特效 spawn·update·remove", _test_signal_forwarding)


static func _move_event(actor_id: String, q: int, r: int, duration: float) -> Dictionary:
	return {"kind": ProbeTranslator.PROBE_MOVE, "actor_id": actor_id, "to": [q, r], "duration": duration}


static func _hit_event(actor_id: String, amount: float, vfx_duration: float = 200.0) -> Dictionary:
	return {"kind": ProbeTranslator.PROBE_HIT, "actor_id": actor_id, "amount": amount, "vfx_duration": vfx_duration}


static func _settled(director: VisualDirector, actor_id: String) -> Vector2:
	var state: ActorVisualState = director.get_actors_snapshot().get(actor_id)
	return state.position


static func _record_changes(director: VisualDirector) -> Array[String]:
	var changed: Array[String] = []
	director.actor_state_changed.connect(func(actor_id: String, _state: ActorVisualState) -> void: changed.append(actor_id))
	return changed


static func _record_spawns(director: VisualDirector) -> Array[String]:
	var spawned: Array[String] = []
	director.actor_spawned.connect(func(actor_id: String, _state: ActorVisualState) -> void: spawned.append(actor_id))
	return spawned


func _test_seed_and_move() -> void:
	var director := LiveProbeDirector.new()
	var spawned := _record_spawns(director)
	var changed := _record_changes(director)

	var u1 := director.seed_probe("u1", Vector2.ZERO, 30.0, 50.0)
	TestFramework.assert_true(u1 != null)
	TestFramework.assert_equal("u1", ",".join(spawned))
	TestFramework.assert_equal("u1", ",".join(changed))
	var snapshot: ActorVisualState = director.get_actors_snapshot()["u1"]
	TestFramework.assert_true(snapshot.position.is_equal_approx(Vector2.ZERO))
	TestFramework.assert_near(snapshot.visual_hp, 30.0)
	TestFramework.assert_near(snapshot.target_hp, 30.0)
	TestFramework.assert_near(snapshot.max_hp, 50.0)
	TestFramework.assert_true(snapshot.is_alive)
	TestFramework.assert_equal("u1", snapshot.display_name)

	# hp / max_hp 缺省：max_hp 1、hp 满
	var u2 := director.seed_probe("u2", Vector2(3.0, -1.0))
	TestFramework.assert_near(u2.max_hp, 1.0)
	TestFramework.assert_near(u2.target_hp, 1.0)
	TestFramework.assert_near(u2.visual_hp, 1.0)
	TestFramework.assert_true(director.get_actor_position("u2").is_equal_approx(Vector2(3.0, -1.0)))

	# 同 id 重复 seed 忽略
	TestFramework.assert_true(director.seed_probe("u1", Vector2(9.0, 9.0)) == null)
	TestFramework.assert_equal(2, spawned.size())
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2.ZERO))
	TestFramework.assert_false(director.is_moving("u1"))
	TestFramework.assert_equal(0, director.get_action_count())

	# 第一条 move (0,0)→(2,0) 200ms：一半时在飞插值到 (1,0)，账本位置未落定，不广播
	changed.clear()
	var events: Array[Dictionary] = [_move_event("u1", 2, 0, 200.0)]
	director.pump(100.0, events)
	TestFramework.assert_true(director.is_moving("u1"))
	TestFramework.assert_equal(1, director.get_action_count())
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2(1.0, 0.0)))
	TestFramework.assert_true(_settled(director, "u1").is_equal_approx(Vector2.ZERO))
	TestFramework.assert_equal(0, changed.size())

	# 没有事件也推动画：走完落定、当场广播一次、翻转为不在飞
	director.pump(100.0, NO_EVENTS)
	TestFramework.assert_false(director.is_moving("u1"))
	TestFramework.assert_equal(0, director.get_action_count())
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2(2.0, 0.0)))
	TestFramework.assert_true(_settled(director, "u1").is_equal_approx(Vector2(2.0, 0.0)))
	TestFramework.assert_equal("u1", ",".join(changed))

	# 第二条 move 从账本当前位置出发（翻译员读只读视图）：(2,0)→(2,2)
	events = [_move_event("u1", 2, 2, 200.0)]
	director.pump(50.0, events)
	TestFramework.assert_true(director.is_moving("u1"))
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2(2.0, 0.5)))
	director.pump(150.0, NO_EVENTS)
	TestFramework.assert_false(director.is_moving("u1"))
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2(2.0, 2.0)))
	# u2 全程没动
	TestFramework.assert_true(director.get_actor_position("u2").is_equal_approx(Vector2(3.0, -1.0)))
	director.free()


func _test_lifecycle_before_translate() -> void:
	var director := LiveProbeDirector.new()
	var spawned := _record_spawns(director)
	var died: Array[String] = []
	director.actor_died.connect(func(actor_id: String) -> void: died.append(actor_id))

	var spawn := {
		"kind": GameEvent.ACTOR_SPAWNED_EVENT, "actor_id": "t1",
		"actor": {"id": "t1", "type": "probe", "position": [3, 3, 0], "attributes": {"hp": 10.0, "max_hp": 10.0}},
	}
	var events: Array[Dictionary] = [spawn, _move_event("t1", 3, 5, 100.0)]
	director.pump(50.0, events)
	TestFramework.assert_equal("t1", ",".join(spawned))
	# 翻译时 t1 已在账上：从 (3,3) 出发而不是未知 actor 的 ZERO
	TestFramework.assert_true(director.get_actor_position("t1").is_equal_approx(Vector2(3.0, 4.0)))
	director.pump(50.0, NO_EVENTS)
	TestFramework.assert_true(director.get_actor_position("t1").is_equal_approx(Vector2(3.0, 5.0)))

	# 同趟 destroy 事件也先落账本：hp 归零、死亡广播一次
	events = [{"kind": GameEvent.ACTOR_DESTROYED_EVENT, "actor_id": "t1"}]
	director.pump(0.0, events)
	TestFramework.assert_equal("t1", ",".join(died))
	var t1: ActorVisualState = director.get_actors_snapshot()["t1"]
	TestFramework.assert_false(t1.is_alive)
	TestFramework.assert_near(t1.target_hp, 0.0)
	director.free()


func _test_cancel_and_snap() -> void:
	var director := LiveProbeDirector.new()
	director.seed_probe("u1", Vector2.ZERO)
	director.seed_probe("u2", Vector2(5.0, 5.0))
	var events: Array[Dictionary] = [_move_event("u1", 4, 0, 400.0), _move_event("u2", 5, 9, 400.0)]
	director.pump(100.0, events)
	TestFramework.assert_true(director.is_moving("u1"))
	TestFramework.assert_true(director.is_moving("u2"))
	TestFramework.assert_equal(2, director.get_action_count())
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2(1.0, 0.0)))
	TestFramework.assert_true(director.get_actor_position("u2").is_equal_approx(Vector2(5.0, 6.0)))

	# 只撤 u1：u2 照走；不补发完成 → 账本位置仍是起点，在飞插值停在撤销那一刻
	director.cancel("u1")
	TestFramework.assert_false(director.is_moving("u1"))
	TestFramework.assert_true(director.is_moving("u2"))
	TestFramework.assert_equal(1, director.get_action_count())
	TestFramework.assert_true(_settled(director, "u1").is_equal_approx(Vector2.ZERO))
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2(1.0, 0.0)))
	director.pump(100.0, NO_EVENTS)
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2(1.0, 0.0)))
	TestFramework.assert_true(director.get_actor_position("u2").is_equal_approx(Vector2(5.0, 7.0)))

	# 撤销未知 actor 无事
	director.cancel("ghost")
	TestFramework.assert_equal(1, director.get_action_count())

	# snap = 撤销 + 直接定位：账本与在飞插值一起写、当场广播
	var changed := _record_changes(director)
	director.snap("u2", Vector2.ZERO)
	TestFramework.assert_false(director.is_moving("u2"))
	TestFramework.assert_equal(0, director.get_action_count())
	TestFramework.assert_true(director.get_actor_position("u2").is_equal_approx(Vector2.ZERO))
	TestFramework.assert_true(_settled(director, "u2").is_equal_approx(Vector2.ZERO))
	TestFramework.assert_equal("u2", ",".join(changed))
	director.free()


func _test_despawn() -> void:
	var director := LiveProbeDirector.new()
	var spawned := _record_spawns(director)
	var despawned: Array[String] = []
	director.actor_despawned.connect(func(actor_id: String) -> void: despawned.append(actor_id))
	director.seed_probe("u1", Vector2.ZERO)
	director.seed_probe("u2", Vector2(1.0, 1.0))
	var events: Array[Dictionary] = [_move_event("u1", 4, 0, 400.0)]
	director.pump(100.0, events)

	director.despawn("u1")
	TestFramework.assert_equal("u1", ",".join(despawned))
	TestFramework.assert_false(director.get_actors_snapshot().has("u1"))
	TestFramework.assert_true(director.get_actors_snapshot().has("u2"))
	TestFramework.assert_false(director.is_moving("u1"))
	TestFramework.assert_equal(0, director.get_action_count())
	# 出账后是未知 actor：位置回默认
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2.ZERO))

	director.despawn("ghost")
	TestFramework.assert_equal(1, despawned.size())
	director.pump(100.0, NO_EVENTS)

	# 同 id 可重新入账
	TestFramework.assert_true(director.seed_probe("u1", Vector2(5.0, 5.0)) != null)
	TestFramework.assert_equal("u1,u2,u1", ",".join(spawned))
	TestFramework.assert_true(director.get_actor_position("u1").is_equal_approx(Vector2(5.0, 5.0)))
	director.free()


func _test_signal_forwarding() -> void:
	var director := LiveProbeDirector.new()
	director.seed_probe("u1", Vector2(2.0, 2.0), 15.0, 20.0)
	var changed := _record_changes(director)
	var died: Array[String] = []
	director.actor_died.connect(func(actor_id: String) -> void: died.append(actor_id))
	var spawned_fx: Array[String] = []
	var updated_fx: Array[String] = []
	var removed_fx: Array[String] = []
	director.effect_spawned.connect(func(kind: StringName, _payload: VisualEffectPayload.Effect) -> void:
		spawned_fx.append(String(kind)))
	director.effect_updated.connect(func(kind: StringName, _effect_id: String, progress: float, _payload: VisualEffectPayload.Effect) -> void:
		updated_fx.append("%s@%.1f" % [kind, progress]))
	director.effect_removed.connect(func(kind: StringName, _effect_id: String) -> void:
		removed_fx.append(String(kind)))

	# 一击 10：target_hp 15→5，visual_hp 追赶途中（本趟标脏 flush 一次）；飘字 + 攻击特效入账，特效每趟 update
	var events: Array[Dictionary] = [_hit_event("u1", 10.0, 200.0)]
	director.pump(100.0, events)
	var u1: ActorVisualState = director.get_actors_snapshot()["u1"]
	TestFramework.assert_near(u1.target_hp, 5.0)
	TestFramework.assert_true(u1.visual_hp < 15.0 and u1.visual_hp > 5.0, "visual_hp 在追赶途中: %f" % u1.visual_hp)
	TestFramework.assert_true(u1.is_alive)
	TestFramework.assert_equal(0, died.size())
	TestFramework.assert_equal("u1", ",".join(changed))
	spawned_fx.sort()
	TestFramework.assert_equal("attack_vfx,floating_text", ",".join(spawned_fx))
	TestFramework.assert_equal("attack_vfx@0.5", ",".join(updated_fx))
	TestFramework.assert_equal(0, removed_fx.size())

	# 攻击特效走完：update 1.0 后 remove；飘字仍在账（500ms）
	director.pump(100.0, NO_EVENTS)
	TestFramework.assert_equal("attack_vfx@0.5,attack_vfx@1.0", ",".join(updated_fx))
	TestFramework.assert_equal("attack_vfx", ",".join(removed_fx))

	# 致死一击：actor_died 一次（transition-only），再打不重发（攻击特效时长 0：当趟入账即出账）
	events = [_hit_event("u1", 50.0, 0.0)]
	director.pump(0.0, events)
	TestFramework.assert_equal("u1", ",".join(died))
	u1 = director.get_actors_snapshot()["u1"]
	TestFramework.assert_false(u1.is_alive)
	TestFramework.assert_near(u1.target_hp, 0.0)
	director.pump(0.0, events)
	TestFramework.assert_equal(1, died.size())

	# 只剩三张飘字卡片（500ms）在飞：走完 + 到期由账本静默忘记，不发 effect_removed
	var removed_before := removed_fx.size()
	director.pump(1000.0, NO_EVENTS)
	TestFramework.assert_equal(0, director.get_action_count())
	TestFramework.assert_equal(removed_before, removed_fx.size())
	director.free()
