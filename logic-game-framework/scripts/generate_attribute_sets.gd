extends Node
## Headless 属性集生成入口。用法：
##   godot --headless --path . addons/logic-game-framework/scripts/generate_attribute_sets.tscn
## 退出码 0 = 全部 config 生成成功；1 = 任一 config 失败或 set 名冲突。
## 编辑器内等价操作：Tools > LGFramework > 生成属性集。


func _ready() -> void:
	var ok := AttributeSetGeneratorScript.generate_all()
	print("ATTRIBUTE_GEN_RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
