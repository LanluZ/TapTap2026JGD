class_name Production
extends Component
## 生产/合成（§4）：按 recipe_id 周期开工。
## active：本周期是否已扣输入开工（扣款开产 → 产出进缓冲；欠料欠电则不开工）。
## progress：本周期已进行时间。

var recipe_id: StringName = &""
var progress: float = 0.0
var interval: float = 0.0 # 单次生产周期（秒）
var hydro: StringName = &"hydro_none" # 亲水基因：hydro_love / hydro_thirsty / hydro_none（断水惩罚由系统读取）
var hydro2: StringName = &"" # 第二条水基因（亲水座杂合时才有；空 = 无）
var alt: Dictionary = {} # 第二配方通道 {recipe_id, interval, progress, active}；空 = 单配方
var active: bool = false
