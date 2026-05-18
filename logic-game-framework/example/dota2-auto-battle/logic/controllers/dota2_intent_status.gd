## Dota2IntentStatus - current intent 生命周期状态（controller-intent-model.md）
##
## controller 拥有 current_intent_status；systems 报告 step 事实，controller 据此推进。
class_name Dota2IntentStatus
extends RefCounted


const NONE := "none"
const RUNNING := "running"
const COMPLETED := "completed"
const FAILED := "failed"
const INTERRUPTED := "interrupted"
