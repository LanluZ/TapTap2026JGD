class_name Health
extends Component
## 生命值（§4）。pending_damage：本帧已命中、待 DamageSystem（#9）统一结算的伤害。

var hp: float = 0.0
var max_hp: float = 0.0
var pending_damage: float = 0.0
