class_name Entity
extends RefCounted
## 实体（架构文档 §3）：实体 = int id，仅是句柄，本类不承载实例数据。
## §2 entity.gd 要求的「组件位标记」：这里维护 组件类型 → 位 标注表，
## World 用它给每个实体保存组件位掩码，供多组件快速判断（如 Production ∩ ResourceBuffer）。


static var _bit_by_type: Dictionary = {} # StringName 组件类型 -> int 位
static var _next_shift: int = 0

## 取（或分配）组件类型的位标记。位数上限 62，超出即报错。
static func bit_for(t: StringName) -> int:
	if not _bit_by_type.has(t):
		if _next_shift >= 62:
			push_error("Entity: 组件类型位标记超过上限 62（类型=%s）" % String(t))
			return 0
		_bit_by_type[t] = 1 << _next_shift
		_next_shift += 1
	return int(_bit_by_type[t])
