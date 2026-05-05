class_name SimNavPathfinderHeap


static func insert(arr: Array, key: Array) -> void:
	var lo := 0
	var hi := arr.size()
	while lo < hi:
		@warning_ignore("integer_division")
		var mid: int = (lo + hi) / 2
		if key_less(arr[mid], key):
			lo = mid + 1
		else:
			hi = mid
	arr.insert(lo, key)


static func key_less(a: Array, b: Array) -> bool:
	for i in range(5):
		if a[i] < b[i]:
			return true
		if a[i] > b[i]:
			return false
	return false
