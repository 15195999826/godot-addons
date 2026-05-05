class_name SimNavRegionIdHelper


const CI_SHIFT: int = 40
const CJ_SHIFT: int = 16
const CI_BITS: int = 24
const CJ_BITS: int = 24
const R_BITS: int = 16
const CI_MASK: int = (1 << CI_BITS) - 1
const CJ_MASK: int = (1 << CJ_BITS) - 1
const R_MASK: int = (1 << R_BITS) - 1
const INVALID: int = 0


static func pack(ci: int, cj: int, r: int) -> int:
	return (ci << CI_SHIFT) | (cj << CJ_SHIFT) | r


static func unpack_ci(rid: int) -> int:
	return (rid >> CI_SHIFT) & CI_MASK


static func unpack_cj(rid: int) -> int:
	return (rid >> CJ_SHIFT) & CJ_MASK


static func unpack_r(rid: int) -> int:
	return rid & R_MASK


static func is_invalid(rid: int) -> bool:
	return (rid & R_MASK) == 0
