extends Node

## TranslatorRegistry（翻译员注册表）的分发合同钉子
##
## 钉住合同：
## - translate 走遍所有注册的翻译员，能处理的按注册顺序各出一份、结果拼接（collect-all，不是首个命中即停）
## - can_handle 为 false 的翻译员不被调用；没人能处理时返回空数组
## - has_translator_for / get_translators_for 只看 kind（拿 {kind} 探针事件问 can_handle）
## - translate_all 按事件顺序拼接；register / register_all / set_debug_mode 返回自身可链式
## - hex 默认注册表：12 个翻译员；damage 由飘字 / buff / 护盾三家协作；actor_spawned / actor_destroyed
##   这类生命周期事件没人翻译（由 VisualUpdater.apply_event 直改账本）


class StubTranslator extends Translator:
	var kind: String
	var cards: int
	var calls: int = 0

	func _init(p_name: String, p_kind: String, p_cards: int) -> void:
		translator_name = p_name
		kind = p_kind
		cards = p_cards

	func can_handle(event: Dictionary) -> bool:
		return get_event_kind(event) == kind

	func translate(_event: Dictionary, _query: VisualStateQuery) -> Array[VisualAction]:
		calls += 1
		var out: Array[VisualAction] = []
		for i in range(cards):
			var card := VisualAction.new(VisualAction.KIND_MOVE, 0.0, 0.0)
			card.actor_id = "%s#%d" % [translator_name, i]
			out.append(card)
		return out


func _init() -> void:
	TestFramework.register_test("TranslatorRegistry translate 收集所有能处理的翻译员结果，按注册顺序拼接", _test_collect_all)
	TestFramework.register_test("TranslatorRegistry has_translator_for / get_translators_for 只看 kind，注册链式返回自身", _test_queries)
	TestFramework.register_test("TranslatorRegistry translate_all 按事件顺序拼接", _test_translate_all)
	TestFramework.register_test("TranslatorRegistry hex 默认注册表 12 员，damage 三家协作，生命周期事件无人翻译", _test_default_registry)


static func _ids(actions: Array[VisualAction]) -> String:
	var ids: Array[String] = []
	for action in actions:
		ids.append(action.actor_id)
	return ",".join(ids)


func _test_collect_all() -> void:
	var a := StubTranslator.new("A", "ping", 1)
	var b := StubTranslator.new("B", "ping", 2)
	var c := StubTranslator.new("C", "pong", 5)
	var registry := TranslatorRegistry.new().register(a).register(b).register(c)

	var actions := registry.translate({"kind": "ping"}, null)
	TestFramework.assert_equal("A#0,B#0,B#1", _ids(actions))
	TestFramework.assert_equal(1, a.calls)
	TestFramework.assert_equal(1, b.calls)
	# can_handle 为 false 的翻译员不被调用
	TestFramework.assert_equal(0, c.calls)

	TestFramework.assert_equal(0, registry.translate({"kind": "nobody"}, null).size())
	# 缺 kind 的事件没人管
	TestFramework.assert_equal(0, registry.translate({}, null).size())


func _test_queries() -> void:
	var a := StubTranslator.new("A", "ping", 1)
	var c := StubTranslator.new("C", "pong", 1)
	var registry := TranslatorRegistry.new()
	TestFramework.assert_true(registry.register(a) == registry, "register 返回自身")
	var more: Array[Translator] = [c]
	TestFramework.assert_true(registry.register_all(more) == registry, "register_all 返回自身")
	TestFramework.assert_true(registry.set_debug_mode(false) == registry, "set_debug_mode 返回自身")

	TestFramework.assert_true(registry.has_translator_for("ping"))
	TestFramework.assert_true(registry.has_translator_for("pong"))
	TestFramework.assert_false(registry.has_translator_for("nobody"))
	TestFramework.assert_equal("A", ",".join(registry.get_translators_for("ping")))
	TestFramework.assert_equal("", ",".join(registry.get_translators_for("nobody")))
	TestFramework.assert_equal(2, registry.get_count())
	TestFramework.assert_equal("A,C", ",".join(registry.get_registered_names()))
	# 查询不触发 translate
	TestFramework.assert_equal(0, a.calls + c.calls)


func _test_translate_all() -> void:
	var a := StubTranslator.new("A", "ping", 1)
	var c := StubTranslator.new("C", "pong", 2)
	var registry := TranslatorRegistry.new().register(a).register(c)
	var events: Array[Dictionary] = [{"kind": "pong"}, {"kind": "ping"}, {"kind": "nobody"}, {"kind": "ping"}]
	TestFramework.assert_equal("C#0,C#1,A#0,A#0", _ids(registry.translate_all(events, null)))
	TestFramework.assert_equal(2, a.calls)
	TestFramework.assert_equal(1, c.calls)


func _test_default_registry() -> void:
	var registry := FrontendDefaultRegistry.create()
	TestFramework.assert_equal(12, registry.get_count())
	TestFramework.assert_true(registry.has_translator_for(BattleEvents.DAMAGE_EVENT))
	TestFramework.assert_true(registry.has_translator_for(BattleEvents.MOVE_START_EVENT))
	TestFramework.assert_true(registry.has_translator_for(BattleEvents.DEATH_EVENT))
	TestFramework.assert_true(registry.has_translator_for(GameEvent.STAGE_CUE_EVENT))
	TestFramework.assert_true(registry.has_translator_for(GameEvent.ABILITY_GRANTED_EVENT))
	TestFramework.assert_false(registry.has_translator_for(GameEvent.ACTOR_SPAWNED_EVENT), "生命周期事件由 VisualUpdater.apply_event 直改，不经翻译员")
	TestFramework.assert_false(registry.has_translator_for(GameEvent.ACTOR_DESTROYED_EVENT))
	TestFramework.assert_false(registry.has_translator_for(GameEvent.ATTRIBUTE_CHANGED_EVENT))
	# damage 由飘字 / buff 消耗 / 护盾消耗三家按注册顺序协作
	TestFramework.assert_equal(
		"DamageTranslator,BuffTranslator,ShieldBarTranslator",
		",".join(registry.get_translators_for(BattleEvents.DAMAGE_EVENT))
	)
