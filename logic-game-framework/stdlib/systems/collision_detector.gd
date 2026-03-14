class_name CollisionDetector
extends RefCounted
## 碰撞检测器基类
##
## 当前实现为 O(n) 线性遍历所有潜在目标，适用于少量投射物场景（<20）。
##
## 【性能优化方案（投射物数量 > 50 时考虑）】
##
## 方案 1: 空间分区 Grid
##   - 将战场划分为固定大小的格子（如 100×100 单位）
##   - 每帧将所有 Actor 按位置注册到对应格子
##   - 碰撞检测时只检查投射物所在格子及相邻格子的 Actor
##   - 复杂度从 O(projectiles × targets) 降为 O(projectiles × avg_targets_per_cell)
##   - 预期性能提升 80-90%
##
## 方案 2: 按阵营/类型预过滤
##   - ProjectileSystem.tick() 中按 team 预分组 Actor
##   - 投射物只检测敌方阵营的 Actor
##   - 实现简单，适合阵营明确的战斗场景
##
## 方案 3: 宽阶段 + 窄阶段（Broad Phase + Narrow Phase）
##   - 宽阶段：AABB 包围盒快速排除不可能碰撞的对
##   - 窄阶段：精确距离检测
##   - 适合投射物和目标体积差异大的场景

func detect(projectile: ProjectileActor, potential_targets: Array[Actor]) -> Dictionary:
	push_error("CollisionDetector is abstract and must be overridden")
	return {"hit": false}
