class_name PathFollower
extends Component
## 敌人沿环形路径循环前进（§4）。
## 减速地块 / DEBUFF 以乘区施加，不改写 speed 基值。

var path_id: StringName = &"" # 关卡路径 id（levels.json path_id）
var distance: float = 0.0 # 当前弧长（世界单位），环形自动回绕
var speed: float = 0.0 # 基础速度（单位/秒）
