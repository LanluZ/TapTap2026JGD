class_name ResourceBuffer
extends Component
## 资源缓冲（§4）：工厂产出先进缓冲，按 flush_interval 定期汇入玩家资源池（§7）。

var stored: Dictionary = {} # resource_id(StringName) -> int
var flush_interval: float = 0.0 # 汇入周期（秒，蓝图配置必填）
var flush_timer: float = 0.0


func add(resource_id: StringName, amount: int) -> void:
	stored[resource_id] = int(stored.get(resource_id, 0)) + amount
