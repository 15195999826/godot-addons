## Dota2Intent - 持久 current intent（README.md（Controller / Intent 模型 节））
##
## Brain decision → Dota2Intent → 存为 controller.current_intent → systems 每 tick 推进。
## intent_id 让 systems 区分"继续同一 intent"与"开始新 intent"（movement adapter 据此
## 决定是否复用 path-following runtime）。M1 词汇只两种：LANE_MARCH / ATTACK_TARGET。
##
## payload 约定：
##   LANE_MARCH:    { "lane_goal": Vector2 }
##   ATTACK_TARGET: { "target_id": String }   ← 权威攻击目标，actor 字段只能镜像不能另立真相
class_name Dota2Intent
extends RefCounted


const KIND_LANE_MARCH := "lane_march"
const KIND_ATTACK_TARGET := "attack_target"

const PRIORITY_MARCH := 0
const PRIORITY_ATTACK := 10


static var _next_intent_id: int = 1


var intent_id: int = 0
var kind: String = ""
var created_tick: int = 0
var priority: int = 0
var payload: Dictionary = {}


func _init(p_kind: String, p_created_tick: int, p_priority: int, p_payload: Dictionary) -> void:
	intent_id = _next_intent_id
	_next_intent_id += 1
	kind = p_kind
	created_tick = p_created_tick
	priority = p_priority
	payload = p_payload


static func lane_march(created_tick: int, lane_goal: Vector2) -> Dota2Intent:
	return Dota2Intent.new(KIND_LANE_MARCH, created_tick, PRIORITY_MARCH, { "lane_goal": lane_goal })


static func attack_target(created_tick: int, target_id: String) -> Dota2Intent:
	return Dota2Intent.new(KIND_ATTACK_TARGET, created_tick, PRIORITY_ATTACK, { "target_id": target_id })


## ATTACK_TARGET 的权威目标 id（非该 kind 返回 ""）。
func get_target_id() -> String:
	if kind != KIND_ATTACK_TARGET:
		return ""
	return str(payload.get("target_id", ""))


func get_lane_goal() -> Vector2:
	return payload.get("lane_goal", Vector2.ZERO) as Vector2
