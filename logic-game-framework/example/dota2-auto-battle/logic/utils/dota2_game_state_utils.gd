## Dota2GameStateUtils - 项目层的 GameplayInstance 辅助函数
##
## 与 HexBattleGameStateUtils / InkMonBattleGameStateUtils 对偶：每个项目一个 world(ctx)，
## 把 ExecutionContext.instance 收窄成本项目的世界类型。
class_name Dota2GameStateUtils


## ctx.instance 收窄为 Dota2WorldGameplayInstance。
## 类型不符（含 null：owner 未注册进 GameWorld）属接线错误——响亮报错并返回 null。
static func world(ctx: ExecutionContext) -> Dota2WorldGameplayInstance:
	var world_instance := ctx.instance as Dota2WorldGameplayInstance
	if world_instance == null:
		Log.assert_crash(false, "Dota2GameStateUtils",
			"ctx.instance 不是 Dota2WorldGameplayInstance: %s" % ctx.instance)
	return world_instance
