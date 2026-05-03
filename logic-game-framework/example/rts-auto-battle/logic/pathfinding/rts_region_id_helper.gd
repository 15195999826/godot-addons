## RtsRegionIdHelper - Packed int64 RegionID 编解码 helper (M4 引入)
##
## 0 A.D. `helpers/HierarchicalPathfinder.h` 的 `struct RegionID` (`u8 ci, u8 cj, u16 r`,
## 32-bit packed) 的 GDScript 复刻。**不照搬 32-bit 限制** — Godot int 是 64-bit signed,
## 顺手把 ci / cj 扩到 24 bit,避免 chunks > 256 时溢出(0 A.D. 上限,实际游戏地图远不需要)。
##
## 字段布局(从高位到低位):
##   bits 63..40 (24 bit): ci (chunk i, 0..2^24-1)
##   bits 39..16 (24 bit): cj (chunk j, 0..2^24-1)
##   bits 15..0  (16 bit): r  (chunk 内 local region ID, 0 = impassable / 1..2^16-1 = valid)
##
## **0 表示无效**: `(ci=0, cj=0, r=0)` 是哨兵值,代表 navcell 不可通行 / 越界。注意真正的
## `(ci=0, cj=0, r=N)` chunk 内 region 1 编码成 1,**不是** 0 — `is_invalid` 只看低 16 bit
## 的 r,这样 (0,0) chunk 内 region 不会被误判为 invalid。
##
## **为什么用 packed int 不用 RefCounted 或 String key**:
##   - GDScript Dictionary 用 RefCounted 当 key 走 **实例身份比较**(codex 2026-05-03 本地验证),
##     两个字段相同的实例 `Dictionary.has()` 不命中,无法实现 region edges / global graph
##   - String key 比较远慢于 int (一次 byte-by-byte vs 一次 64-bit cmp)
##   - 决策来源:data-structures.md §4.1 + Q4 (codex P1 #1 拍板)
##
## **调方约束**(本 helper 不放 assert,避免 pack 万次/recompute 的 perf hit):
##   - ci ∈ [0, 2^24-1],由 RtsHierarchicalPathfinder._chunks_w / _chunks_h 上限保证
##   - cj 同上
##   - r ∈ [1, 2^16-1] for valid region,= 0 表示 impassable navcell
##   - 越界值会 silent 截断成低位,导致 RegionID 碰撞
##
## **Determinism**: 整数 `<` 比较跨平台稳定;数组 sort by packed RID 等价 sort by (ci, cj, r)
## 字典序(高位 ci 主导)。
class_name RtsRegionIdHelper
extends RefCounted


# ========== 字段布局常量 ==========

const CI_SHIFT: int = 40
const CJ_SHIFT: int = 16
const CI_BITS: int = 24
const CJ_BITS: int = 24
const R_BITS: int = 16
const CI_MASK: int = (1 << CI_BITS) - 1
const CJ_MASK: int = (1 << CJ_BITS) - 1
const R_MASK: int = (1 << R_BITS) - 1

## 哨兵:`(ci=0, cj=0, r=0)`,表示 navcell 不可通行 / 越界。
## 注意 `(ci=0, cj=0, r=1)` 是合法 RegionID,packed 值 = 1 ≠ INVALID。
const INVALID: int = 0


# ========== 编解码 ==========

## 把 (ci, cj, r) 打包成 int64 RegionID。
##
## 调方负责保证 ci/cj/r 在合法范围(见 §字段布局常量);越界会 silent 截断到低位 → 碰撞。
static func pack(ci: int, cj: int, r: int) -> int:
	return (ci << CI_SHIFT) | (cj << CJ_SHIFT) | r


static func unpack_ci(rid: int) -> int:
	return (rid >> CI_SHIFT) & CI_MASK


static func unpack_cj(rid: int) -> int:
	return (rid >> CJ_SHIFT) & CJ_MASK


static func unpack_r(rid: int) -> int:
	return rid & R_MASK


## RegionID 是否表示无效 / 不可通行。
##
## **只看低 16 bit 的 r** — `(ci=0, cj=0, r=N>0)` 是合法 (0,0) chunk 内 region,
## packed 值 = N ≠ 0,但若误用 `rid == 0` 比较会把它当 invalid。本 helper 总是用 `is_invalid` 取代直接比较。
static func is_invalid(rid: int) -> bool:
	return (rid & R_MASK) == 0
