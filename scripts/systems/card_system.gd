class_name CardSystem
extends System
## #10 卡牌（§5）：DeckState 手牌状态（非实体，§5 说明）；打出后补抽 1 张
## （0 消耗规则 §12，登记于 CommandSystem，本系统在 #10 执行），手牌上限
## hand_max 来自 cards.json，关卡卡池来自 levels.json card_pool。
## 抽卡堆：抽出耗尽后按关卡卡池重新洗牌循环（策划案 §16）。


## 手牌/抽卡堆状态（§5：CardSystem 自己的 DeckState，不进 ECS）。
class DeckState extends RefCounted:
	var hand: Array = [] # 手牌：卡 id(StringName)
	var pool: Array = [] # 抽卡堆：卡 id(StringName)
	var hand_max: int = 0 # cards.json hand_max
	var pending_draw: int = 0 # 已打出、待补的张数


var deck: DeckState = DeckState.new()
var _rng := RandomNumberGenerator.new()
var _card_pool: Array = [] # 关卡卡池（循环补堆用）


func setup(world) -> void:
	if world.config == null or world.state == null or world.config.levels.is_empty():
		push_error("CardSystem.setup: World 未挂载 config/state 或配置未加载")
		return
	var level: Dictionary = world.config.get_level(world.state.level_id)
	if level.is_empty():
		return
	deck.hand_max = world.config.hand_max
	_card_pool = level["card_pool"].duplicate()
	deck.pool = _card_pool.duplicate()
	_rng.randomize()
	_shuffle(deck.pool)
	# 初始手牌：hand_start 张（levels.json，≤ hand_max 已由配置校验）
	while deck.hand.size() < int(level["hand_start"]):
		if not _draw_one():
			break


func tick(world, _dt: float) -> void:
	# CommandSystem（#1）登记的补抽：打出才补，且不超过手牌上限（§13）
	while deck.pending_draw > 0 and deck.hand.size() < deck.hand_max:
		if not _draw_one():
			break
		deck.pending_draw -= 1


## 手牌满则放抽牌堆顶（DNA 融合子代入手通道，规格 §4）；空位直接入手。
func receive_card(card_id: StringName) -> void:
	if deck.hand.size() < deck.hand_max:
		deck.hand.append(card_id)
	else:
		deck.pool.push_front(card_id)


func _draw_one() -> bool:
	if deck.pool.is_empty():
		if _card_pool.is_empty():
			push_error("CardSystem: 关卡卡池为空，无法抽卡")
			return false
		deck.pool = _card_pool.duplicate()
		_shuffle(deck.pool)
	if deck.pool.is_empty():
		return false
	deck.hand.append(deck.pool.pop_back())
	return true


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
