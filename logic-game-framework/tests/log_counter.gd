extends Logger

## 测试用日志计数器：OS.add_logger 挂上、OS.remove_logger 摘下，摘下之后再读计数。
##
## GDScript 运行期错误（含断言失败）只中止出错的那一帧、调用方照常往下走——降级路径「报错中止」与
## 「正常跳过」留下的状态可以完全相同，只有日志通道分得开。errors 数警告以外的全部类型（脚本错误 / 断言 /
## push_error）；matched_errors / matched_warnings 只数文本含 match_text 的那些（断言文本 / 警告文本），
## 「恰好一条某断言、别无其它」= matched_errors == 1 且 errors == 1。回调可能来自任意线程，计数在锁内。

var errors := 0
var matched_errors := 0
var matched_warnings := 0
var _match_text: String
var _mutex := Mutex.new()


func _init(match_text: String = "") -> void:
	_match_text = match_text


func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	_mutex.lock()
	var matched := _match_text != "" and (code + rationale).contains(_match_text)
	if error_type != ERROR_TYPE_WARNING:
		errors += 1
		if matched:
			matched_errors += 1
	elif matched:
		matched_warnings += 1
	_mutex.unlock()
