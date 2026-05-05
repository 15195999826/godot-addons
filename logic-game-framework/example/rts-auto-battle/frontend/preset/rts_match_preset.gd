## RtsMatchPreset - 起手 setup 配置 (M2.3 Phase C).
##
## main_menu 用户选预设 → 实例化 demo_rts_frontend → apply_preset(this) → demo._ready
## 内字段读 preset 替换 hardcode const (resources / num_workers / attach_*_ai /
## show_build_panel). _preset = null 时 demo 走 fallback hardcode (保 frontend smoke
## 路径不破).
##
## 当前 3 预设: 经典 1v1 / 资源紧 1v1 / AI vs AI 观战.
class_name RtsMatchPreset
extends Resource


@export var name: String = ""
@export var description: String = ""

## 起手资源 (左 = 玩家, 右 = AI). 缺 key 视为 0.
@export var starting_resources_left: Dictionary[String, int] = {"gold": 100, "wood": 100}
@export var starting_resources_right: Dictionary[String, int] = {}

## 双方各起手 worker 数 (中立 ResourceNode 始终 4 / 侧).
@export var num_workers_per_team: int = 5

## 是否给左 / 右队伍 attach RtsComputerPlayer.
##   - 经典 1v1: 左玩家 (false), 右 AI (true)
##   - 资源紧 1v1: 同上
##   - AI vs AI 观战: 双 AI (true / true), 玩家不能 build
@export var attach_left_ai: bool = false
@export var attach_right_ai: bool = true

## demo 是否创建 BuildPanel + placement ghost (false 时 AI vs AI observe 模式).
@export var show_build_panel: bool = true

## 起手是否给双方各预放 1 barracks (绕过 RtsComputerPlayer 默认落点跟 CT inflate clearance
## 蹭碰导致的左队 cells_blocked 死锁; 预放后 AI 看 BARRACKS_CAP=1 跳过 build → attack 决策
## 正常). 仅 AI vs AI 模式有意义 (没玩家干预填补 build).
@export var pre_spawn_barracks_each_side: bool = false


# ========== 工厂 (3 预设) ==========

## 经典 1v1 — 与 M2.2 demo 默认体验一致 (双 AI 已 attach, 但玩家可用 BuildPanel 抢放).
##
## 现有 demo _ready 默认双 AI; classic preset 保持双 AI 但保留 BuildPanel — 玩家可与 AI
## 同时 build, 但因 barracks cap=1 通常 AI 抢先 (M2.2 行为延续).
static func create_classic_1v1() -> RtsMatchPreset:
	var p := RtsMatchPreset.new()
	p.name = "Classic 1v1"
	p.description = "Standard skirmish: 100/100 starting resources, 5 workers each, AI plays the right side."
	p.starting_resources_left = {"gold": 100, "wood": 100}
	p.starting_resources_right = {}
	p.num_workers_per_team = 5
	p.attach_left_ai = true
	p.attach_right_ai = true
	p.show_build_panel = true
	return p


## 资源紧 1v1 — 起手 50 gold + 50 wood (不够 1 barracks 80g+50w), 必须先 harvest 补.
## 3 worker 起手 (少劳力, 节奏更慢).
static func create_resource_scarce_1v1() -> RtsMatchPreset:
	var p := RtsMatchPreset.new()
	p.name = "Resource Scarcity"
	p.description = "Tight start: 50/50 resources, 3 workers each. Harvest before building."
	p.starting_resources_left = {"gold": 50, "wood": 50}
	p.starting_resources_right = {}
	p.num_workers_per_team = 3
	p.attach_left_ai = true
	p.attach_right_ai = true
	p.show_build_panel = true
	return p


## AI vs AI 观战 — 玩家不能 build (BuildPanel 隐藏); 双 AI 自跑 → 看战术展开.
##
## 起手 500/500 (够双方各起一个 barracks 立刻开兵) + worker 持续 harvest → 看着金币涨
## (vs Classic 1v1 起手 100/100 一造完 barracks HUD 数字反掉, observe 没 BuildPanel
## 提示就显得"经济停滞").
static func create_ai_vs_ai_observe() -> RtsMatchPreset:
	var p := RtsMatchPreset.new()
	p.name = "AI vs AI Observation"
	p.description = "Spectate two AIs duel — no build panel; pan camera and watch."
	p.starting_resources_left = {"gold": 500, "wood": 500}
	p.starting_resources_right = {"gold": 500, "wood": 500}
	p.num_workers_per_team = 5
	p.attach_left_ai = true
	p.attach_right_ai = true
	p.show_build_panel = false
	p.pre_spawn_barracks_each_side = true
	return p


## 当前 3 预设 (main_menu 显示顺序).
static func all_presets() -> Array[RtsMatchPreset]:
	return [
		create_classic_1v1(),
		create_resource_scarce_1v1(),
		create_ai_vs_ai_observe(),
	]
