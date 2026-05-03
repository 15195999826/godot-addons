## InputHelper - 模拟玩家输入的 headless 测试 helper.
##
## 为什么不直接 emit signal: button.pressed.emit() / button._pressed() 走捷径,
## 漏掉 BaseButton.gui_input 派发链路 / mouse_filter / disabled / modal grab / focus 等真实约束.
## 真模拟输入 (Viewport.push_input + InputEvent*) 才能验证 UI 在玩家视角下能不能用.
##
## 使用前提:
## - headless 默认 window=64×64, Control 锚点居中后 rect 会在 viewport 外, push_input 判定"未击中".
##   smoke 入口 _ready 第一行先 `get_window().size = Vector2i(1280, 720)`, 撑大再 instantiate UI.
## - 调用前 await 1-2 帧让 layout pass 算出 global_rect, 否则 size 可能为 0.
## - main_menu 切换场景时会 queue_free, click 前先缓存要 print 的元数据 (如 button.name),
##   click 后 button 已 invalid.
##
## 用法:
##   const InputHelper = preload(".../tests/ui/input_helper.gd")
##   InputHelper.click_button(self, button)
##   await get_tree().process_frame
class_name InputHelper
extends RefCounted


## 模拟左键 down + up 到指定 viewport 坐标.
## ctx 任意继承 Node 的脚本 (smoke 自身), 用来取 get_viewport().
static func click_at(ctx: Node, pos: Vector2, button_index: int = MOUSE_BUTTON_LEFT) -> void:
	var viewport: Viewport = ctx.get_viewport()

	var press := InputEventMouseButton.new()
	press.button_index = button_index
	press.pressed = true
	press.position = pos
	press.global_position = pos
	viewport.push_input(press)

	var release := InputEventMouseButton.new()
	release.button_index = button_index
	release.pressed = false
	release.position = pos
	release.global_position = pos
	viewport.push_input(release)


## 模拟点击某 Control 的 global_rect 中心. button.disabled / mouse_filter 检查交给引擎.
static func click_control(ctx: Node, control: Control, button_index: int = MOUSE_BUTTON_LEFT) -> void:
	var rect := control.get_global_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		push_error("[InputHelper] click_control: %s has zero global_rect, layout 未算出 (await frame?)" % control.name)
		return
	click_at(ctx, rect.get_center(), button_index)


## 模拟从 from → to 的鼠标拖动 (down at from → motion to → up at to).
## steps = 中间 motion 事件数 (拖框选 / RTS 框选用得到).
static func drag_at(ctx: Node, from: Vector2, to: Vector2, button_index: int = MOUSE_BUTTON_LEFT, steps: int = 4) -> void:
	var viewport: Viewport = ctx.get_viewport()

	var press := InputEventMouseButton.new()
	press.button_index = button_index
	press.pressed = true
	press.position = from
	press.global_position = from
	viewport.push_input(press)

	for i in range(1, steps + 1):
		var t: float = float(i) / float(steps + 1)
		var p: Vector2 = from.lerp(to, t)
		var motion := InputEventMouseMotion.new()
		motion.position = p
		motion.global_position = p
		motion.relative = (to - from) / float(steps + 1)
		motion.button_mask = button_index
		viewport.push_input(motion)

	var release := InputEventMouseButton.new()
	release.button_index = button_index
	release.pressed = false
	release.position = to
	release.global_position = to
	viewport.push_input(release)


## 模拟一次 InputMap action 的 press → release. action 必须在 Project Settings → Input Map 里注册.
## strength 用于摇杆 axis (0..1), 普通按键 1.0.
static func press_action(action: StringName, strength: float = 1.0) -> void:
	Input.action_press(action, strength)
	Input.action_release(action)


## 模拟一次按键按下并立即松开 (走全局 Input → 触发 InputMap 匹配).
## 适合测 hotkey, 不需要先 grab_focus.
static func tap_key(ctx: Node, keycode: Key, ctrl: bool = false, shift: bool = false, alt: bool = false) -> void:
	var viewport: Viewport = ctx.get_viewport()

	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	down.ctrl_pressed = ctrl
	down.shift_pressed = shift
	down.alt_pressed = alt
	viewport.push_input(down)

	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	up.ctrl_pressed = ctrl
	up.shift_pressed = shift
	up.alt_pressed = alt
	viewport.push_input(up)


## 撑大 headless 窗口到 1280×720 (默认 64×64 会让 Control layout 落在 viewport 外).
## smoke 入口 _ready 第一行调一次. 已经手动设过的话调用幂等.
static func ensure_window_size(ctx: Node, size: Vector2i = Vector2i(1280, 720)) -> void:
	var win := ctx.get_window()
	if win.size != size:
		win.size = size
