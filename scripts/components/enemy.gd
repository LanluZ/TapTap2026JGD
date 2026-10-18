class_name Enemy
extends Component
## 敌人标识（§4）：波次归属、普通/精英、掉落数量、已计圈数。

var wave_id: int = -1 # 属于哪一波（0 起；手动创建的测试实体为 -1）
var etype: StringName = &"" # 敌人类型 id（enemies.json，表现层选贴图用）
var elite: bool = false # 精英：掉特殊材料
var flying: bool = false # 飞行：无视地面减速地块与减速 DEBUFF（enemies.json flying）
var loot_id: StringName = &"" # 掉落资源 id（enemies.json loot_id）
var loot_amount: int = 0 # 掉落数量（enemies.json loot_amount）
var laps_done: int = 0 # 已走完的圈数（MovementSystem 累计）
