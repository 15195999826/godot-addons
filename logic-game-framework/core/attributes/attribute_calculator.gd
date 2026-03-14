class_name AttributeCalculator
## 纯静态工具类：属性计算器
##
## 四层公式：currentValue = ((base + addBaseSum) × mulBaseProduct + addFinalSum) × mulFinalProduct


static func calculate(base_value: float, modifiers: Array[AttributeModifier]) -> AttributeBreakdown:
	var add_base_sum := 0.0
	var mul_base_sum := 0.0
	var add_final_sum := 0.0
	var mul_final_sum := 0.0

	for modifier in modifiers:
		match modifier.modifier_type:
			AttributeModifier.Type.ADD_BASE:
				add_base_sum += modifier.value
			AttributeModifier.Type.MUL_BASE:
				mul_base_sum += modifier.value
			AttributeModifier.Type.ADD_FINAL:
				add_final_sum += modifier.value
			AttributeModifier.Type.MUL_FINAL:
				mul_final_sum += modifier.value

	var mul_base_product := 1.0 + mul_base_sum
	var mul_final_product := 1.0 + mul_final_sum
	var body_value := (base_value + add_base_sum) * mul_base_product
	var current_value := (body_value + add_final_sum) * mul_final_product

	return AttributeBreakdown.new(
		base_value,
		add_base_sum,
		mul_base_product,
		body_value,
		add_final_sum,
		mul_final_product,
		current_value,
	)
