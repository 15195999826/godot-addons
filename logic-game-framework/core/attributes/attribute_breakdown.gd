class_name AttributeBreakdown
## 属性计算结果的结构化数据
##
## 替代原来的 Dictionary，提供类型安全的属性分解信息。
## 公式：currentValue = ((base + addBaseSum) × mulBaseProduct + addFinalSum) × mulFinalProduct

var base: float
var add_base_sum: float
var mul_base_product: float
var body_value: float
var add_final_sum: float
var mul_final_product: float
var current_value: float


func _init(
	p_base: float = 0.0,
	p_add_base_sum: float = 0.0,
	p_mul_base_product: float = 1.0,
	p_body_value: float = 0.0,
	p_add_final_sum: float = 0.0,
	p_mul_final_product: float = 1.0,
	p_current_value: float = 0.0,
) -> void:
	base = p_base
	add_base_sum = p_add_base_sum
	mul_base_product = p_mul_base_product
	body_value = p_body_value
	add_final_sum = p_add_final_sum
	mul_final_product = p_mul_final_product
	current_value = p_current_value


## 创建仅有 base 值的 breakdown（无修改器）
static func from_base(base_value: float) -> AttributeBreakdown:
	return AttributeBreakdown.new(base_value, 0.0, 1.0, base_value, 0.0, 1.0, base_value)


## 创建一个 current_value 被 clamp 后的副本
func with_clamped_value(clamped: float) -> AttributeBreakdown:
	return AttributeBreakdown.new(
		base, add_base_sum, mul_base_product, body_value,
		add_final_sum, mul_final_product, clamped,
	)
