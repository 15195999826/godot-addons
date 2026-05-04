## RtsPathfinderHeap - SortedArray-based heap helper(LongPath / VertexPath 复用)
##
## GDScript 没真 priority queue,我们用 SortedArray + bsearch+insert 模拟。`insert(arr, key)`
## 保 ascending lex order;`remove_at(0)` 弹 min(O(N) 但 demo 规模够用,K1 决策见 LongPath docstring)。
##
## **Lex compare key 约定**:
##   - 5 元组 lex `[k0, k1, k2, k3, k4]`(`key_less` 只比前 5 项)
##   - LongPath: `[f, h, i, j, insertion_seq]` (i, j = navcell 整数)
##   - VertexPath: `[f, h, vx_int, vy_int, insertion_seq]` (vx_int = round(x*10) 整数化)
##   - 6th+ 元素是 caller payload(vertex idx / packed cell 等),不进 key 比较
##
## **不变量**:5 项内严格 < 即 a < b;不能是 < 或 <= 的 stable sort 概念,因为 `insertion_seq` 单调递增
## 已确保所有相同 key 都能 distinct(equal-key 永远不发生在两个不同插入间)。
##
## **决策来源**:LongPath / Vertex 两份 _heap_insert / _key_less 完全字面相同(M6a simplify pass
## 发现),抽 static helper 消重 — GDScript class_name + static 跨 class 是规范 reuse 模式。
class_name RtsPathfinderHeap
extends RefCounted


## Bsearch + insert 维持 ascending lex order;每次插入 O(log N) bsearch + O(N) memmove。
##
## `key` 必须至少 5 元素(前 5 进 lex compare);6th+ 是 caller payload。
static func insert(arr: Array, key: Array) -> void:
	var lo: int = 0
	var hi: int = arr.size()
	while lo < hi:
		@warning_ignore("integer_division")
		var mid: int = (lo + hi) / 2
		if key_less(arr[mid], key):
			lo = mid + 1
		else:
			hi = mid
	arr.insert(lo, key)


## 5 元组 lex compare(只比前 5 项;6th+ payload 不进 key)。严格 < ;相等返 false。
static func key_less(a: Array, b: Array) -> bool:
	for i in range(5):
		if a[i] < b[i]:
			return true
		if a[i] > b[i]:
			return false
	return false
