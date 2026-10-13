class_name GameState
extends RefCounted
## 玩家级世界状态（§7）：资源钱包 + 全局状态。
## 非实体组件（手牌、钱包不是游戏世界对象），由关卡 bootstrap 创建并挂到 World.state。


const STATUS_PLAYING := "playing"
const STATUS_WON := "won"
const STATUS_LOST := "lost"

var level_id: StringName = &"" # 当前关卡（levels.json id）
var status: String = STATUS_PLAYING # playing | won | lost
var resources: Dictionary = {} # resource_id(StringName) -> int
var waves_survived: int = 0 # WaveSystem 写入，供 UI 读取
var enemies_on_path: int = 0 # WaveSystem 每帧写入


func is_playing() -> bool:
	return status == STATUS_PLAYING


func get_amount(resource_id: StringName) -> int:
	return int(resources.get(resource_id, 0))


func add(resource_id: StringName, amount: int) -> void:
	resources[resource_id] = get_amount(resource_id) + amount


func can_afford(cost: Dictionary) -> bool:
	for rid in cost:
		if get_amount(StringName(rid)) < int(cost[rid]):
			return false
	return true


## 足额则扣除并返回 true；不足则不动钱包返回 false。
func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for rid in cost:
		var rid_s := StringName(rid)
		resources[rid_s] = get_amount(rid_s) - int(cost[rid])
	return true


## 仅用于指令失败回滚（如卡牌已扣费但放置失败）。
func refund(cost: Dictionary) -> void:
	for rid in cost:
		add(StringName(rid), int(cost[rid]))
