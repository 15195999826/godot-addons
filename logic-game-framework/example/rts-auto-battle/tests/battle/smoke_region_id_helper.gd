## RtsRegionIdHelper unit smoke (M4a.1 — AC1 boundary case)
##
## 验证 packed int64 RegionID 编解码:
##
## - pack/unpack 可逆 (任意 ci/cj/r 组合)
## - INVALID = 0 哨兵
## - (ci=0, cj=0, r=N>0) 不是 INVALID (spec §4.1 关键边界)
## - is_invalid 只看低 16 bit r
## - ci / cj / r 字段不互相干扰 (位布局正确)
##
## 不依赖 GameWorld / autoload — 纯静态函数单元 smoke。
extends Node


var _failures: Array[String] = []


func _ready() -> void:
	GameWorld.init()

	_test_pack_unpack_roundtrip()
	_test_invalid_sentinel()
	_test_isolated_field_no_interference()
	_test_field_max_values()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - region_id_helper boundary cases — pack/unpack/invalid/field-isolation OK")
		get_tree().quit(0)
	else:
		var msg: String = "SMOKE_TEST_RESULT: FAIL - " + ", ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# ========== Test cases ==========

func _test_pack_unpack_roundtrip() -> void:
	var cases: Array = [
		[0, 0, 1],           # 最小合法 region (ci=0 / cj=0 / r=1)
		[1, 1, 1],
		[7, 13, 42],         # 普通值
		[100, 200, 65535],   # r 最大
		[12345, 67890, 1],
	]
	for tc in cases:
		var ci: int = tc[0]
		var cj: int = tc[1]
		var r: int = tc[2]
		var rid: int = RtsRegionIdHelper.pack(ci, cj, r)
		var u_ci: int = RtsRegionIdHelper.unpack_ci(rid)
		var u_cj: int = RtsRegionIdHelper.unpack_cj(rid)
		var u_r: int = RtsRegionIdHelper.unpack_r(rid)
		if u_ci != ci or u_cj != cj or u_r != r:
			_failures.append("roundtrip pack(%d,%d,%d)=%d → unpack=(%d,%d,%d)" % [ci, cj, r, rid, u_ci, u_cj, u_r])


func _test_invalid_sentinel() -> void:
	# INVALID = 0
	if RtsRegionIdHelper.INVALID != 0:
		_failures.append("INVALID expected 0 got %d" % RtsRegionIdHelper.INVALID)

	# pack(0, 0, 0) == INVALID
	var rid_zero: int = RtsRegionIdHelper.pack(0, 0, 0)
	if rid_zero != RtsRegionIdHelper.INVALID:
		_failures.append("pack(0,0,0) expected INVALID(0) got %d" % rid_zero)
	if not RtsRegionIdHelper.is_invalid(rid_zero):
		_failures.append("is_invalid(pack(0,0,0)) expected true")

	# (ci=0, cj=0, r=1) ≠ INVALID — spec §4.1 关键边界
	var rid_origin_r1: int = RtsRegionIdHelper.pack(0, 0, 1)
	if rid_origin_r1 == RtsRegionIdHelper.INVALID:
		_failures.append("pack(0,0,1) should not equal INVALID; got %d" % rid_origin_r1)
	if RtsRegionIdHelper.is_invalid(rid_origin_r1):
		_failures.append("is_invalid(pack(0,0,1)) expected false (origin chunk region 1 is valid)")
	if rid_origin_r1 != 1:
		_failures.append("pack(0,0,1) expected packed value 1 got %d" % rid_origin_r1)

	# (ci > 0, cj > 0, r=0) — chunk 内 cell impassable, is_invalid 为 true (r=0)
	var rid_impassable: int = RtsRegionIdHelper.pack(5, 7, 0)
	if not RtsRegionIdHelper.is_invalid(rid_impassable):
		_failures.append("is_invalid(pack(5,7,0)) expected true (r=0 = impassable)")


func _test_isolated_field_no_interference() -> void:
	# 改 ci 不影响 cj / r 解码
	var rid_a: int = RtsRegionIdHelper.pack(1, 0, 0)
	var rid_b: int = RtsRegionIdHelper.pack(2, 0, 0)
	if RtsRegionIdHelper.unpack_cj(rid_a) != 0 or RtsRegionIdHelper.unpack_r(rid_a) != 0:
		_failures.append("ci=1 leaks into cj/r: pack(1,0,0)=%d cj=%d r=%d" % [
			rid_a,
			RtsRegionIdHelper.unpack_cj(rid_a),
			RtsRegionIdHelper.unpack_r(rid_a),
		])
	if RtsRegionIdHelper.unpack_cj(rid_b) != 0 or RtsRegionIdHelper.unpack_r(rid_b) != 0:
		_failures.append("ci=2 leaks into cj/r")

	# 改 cj 不影响 ci / r
	var rid_c: int = RtsRegionIdHelper.pack(0, 1, 0)
	if RtsRegionIdHelper.unpack_ci(rid_c) != 0 or RtsRegionIdHelper.unpack_r(rid_c) != 0:
		_failures.append("cj=1 leaks into ci/r")

	# 改 r 不影响 ci / cj
	var rid_d: int = RtsRegionIdHelper.pack(0, 0, 1234)
	if RtsRegionIdHelper.unpack_ci(rid_d) != 0 or RtsRegionIdHelper.unpack_cj(rid_d) != 0:
		_failures.append("r=1234 leaks into ci/cj")


func _test_field_max_values() -> void:
	# r 最大值 = R_MASK = 65535
	var rid_max_r: int = RtsRegionIdHelper.pack(0, 0, RtsRegionIdHelper.R_MASK)
	if RtsRegionIdHelper.unpack_r(rid_max_r) != RtsRegionIdHelper.R_MASK:
		_failures.append("max r roundtrip failed: %d" % RtsRegionIdHelper.unpack_r(rid_max_r))

	# ci 较大值 (实际游戏远不会到 CI_MASK; 选 12345 测试位布局)
	var rid_large_ci: int = RtsRegionIdHelper.pack(12345, 0, 1)
	if RtsRegionIdHelper.unpack_ci(rid_large_ci) != 12345:
		_failures.append("ci=12345 roundtrip failed: %d" % RtsRegionIdHelper.unpack_ci(rid_large_ci))

	# 同 (ci, cj) 不同 r 的 packed 比较 — sort by packed RID == sort by (ci, cj, r) 字典序
	var rid_x: int = RtsRegionIdHelper.pack(5, 5, 3)
	var rid_y: int = RtsRegionIdHelper.pack(5, 5, 4)
	var rid_z: int = RtsRegionIdHelper.pack(5, 6, 1)
	if not (rid_x < rid_y):
		_failures.append("packed sort: rid_x=pack(5,5,3) should < rid_y=pack(5,5,4); got %d vs %d" % [rid_x, rid_y])
	if not (rid_y < rid_z):
		_failures.append("packed sort: rid_y=pack(5,5,4) should < rid_z=pack(5,6,1); got %d vs %d" % [rid_y, rid_z])
