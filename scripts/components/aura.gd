class_name Aura
extends Component
## 光环（§4）：radius 半径内，按 target_mask 对目标施加/刷新 effect_id 对应效果。
## 施加对象：给工厂 BUFF（mask=FACTORY）/ 给路径敌人 DEBUFF（mask=ENEMY）。

var radius: float = 0.0 # 世界单位半径
var effect_id: StringName = &"" # buffs.json 中的效果 id
var target_mask: int = 0 # 目标位掩码（GameConfig.MASK_*）
var alt: Dictionary = {} # 第二光环 {radius, effect_id, target_mask}；空 = 单光环
