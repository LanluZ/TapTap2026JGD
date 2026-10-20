extends SceneTree
## headless 验证全局 BGM（autoload Bgm）：注册项、单例在场、初始播 title.ogg、
## 按曲目切歌（title / battle）后循环点与文件元数据 LOOPSTART/LOOPLENGTH 一致、
## beat_count/bpm 反推出的循环终点正确、真流实际回跳（合成 1.0s→2.0s 循环点等回跳）。
##
## 运行：
##   godot --headless --path <项目目录> -s res://tests/bgm_test.gd
## 退出码：0 = 全部通过；非 0 = 失败项数。
##
## 回环探针用 AudioStreamOggVorbis.load_from_file 开新实例并压到 -80dB，
## 不碰 /root/Bgm 单例正在播的共享流。

var _checks: int = 0
var _failures: int = 0
var _phase: int = 0 # 0=静态断言+起探针 1=等回跳 2=汇总退出
var _probe: AudioStreamPlayer
var _start_ms: int = 0
var _prev_pos: float = 0.0
var _wrapped: bool = false


func _process(_dt: float) -> bool:
	match _phase:
		0:
			_phase = 1
			_static_checks()
			_start_probe()
		1:
			_poll_probe()
		2:
			quit(_summary())
			return true
	return false # 运行中返回 true 会让主循环直接退出


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] " + label)
	else:
		_failures += 1
		printerr("  [FAIL] " + label)


func _summary() -> int:
	print("======== 汇总: %d 项检查, %d 项失败 =======" % [_checks, _failures])
	return _failures


func _static_checks() -> void:
	print("======== Bgm BGM 自检 ========")
	var cfg := FileAccess.get_file_as_string("res://project.godot")
	_ok(cfg.contains('Bgm="*res://scripts/ui/bgm.gd"'),
		"project.godot 已注册 autoload Bgm")

	var bgm := root.get_node_or_null("Bgm")
	_ok(bgm != null, "/root/Bgm 单例存在（-s 会实例化 autoload）")
	if bgm == null:
		_phase = 2
		return
	var script: GDScript = load("res://scripts/ui/bgm.gd")
	_ok(script != null and bgm.get_script() == script, "Bgm 挂的是 bgm.gd")

	# 播放器在播、初始曲是 title.ogg（菜单/选关）
	var player := bgm.get_node_or_null("BgmPlayer") as AudioStreamPlayer
	_ok(player != null, "BgmPlayer 播放器存在")
	if player == null:
		_phase = 2
		return
	_ok(player.playing, "BGM 正在播放")
	_ok(_stream_path(player.stream).ends_with("title.ogg"), "初始播放流是 res://sounds/title.ogg")

	# 每首曲子：切过去 → 循环点 = 元数据反推值
	for id in script.TRACKS:
		_track_checks(bgm, player, script, id)
	bgm.play_title() # 复位；后续回环探针用独立新流


## 单曲断言：切歌后在播的就是它，且循环起终点与 .ogg 元数据标签一致
func _track_checks(bgm: Node, player: AudioStreamPlayer, script: GDScript, id: StringName) -> void:
	var cfg: Dictionary = script.TRACKS[id]
	var path := String(cfg["path"])
	var start_frame := int(cfg["loop_start"])
	var end_frame := int(cfg["loop_end"])

	bgm.play(id)
	var stream := player.stream as AudioStreamOggVorbis
	_ok(stream != null and _stream_path(stream).ends_with(path.get_file()),
		"切到 %s 后播放流是 %s" % [id, path])
	if stream == null:
		return
	_ok(stream.loop, "%s: stream.loop=true" % id)
	_ok(absf(stream.loop_offset - start_frame / script.RATE) < 0.001,
		"%s: loop_offset = LOOPSTART(%d帧) → %.6fs" % [id, start_frame, stream.loop_offset])
	_ok(stream.beat_count == script.BEATS_FOR_END,
		"%s: beat_count = 反推拍数 %d" % [id, script.BEATS_FOR_END])
	var end_sec := stream.beat_count * 60.0 / stream.bpm
	_ok(absf(end_sec - end_frame / script.RATE) < 0.001,
		"%s: beat_count×60/bpm = LOOPEND(%d帧) → %.6fs" % [id, end_frame, end_sec])

	# 常量与文件元数据一致（防抄错 LOOPSTART/LOOPLENGTH）
	_ok(String(stream.tags.get("loopstart", "")) == str(start_frame),
		"%s: 元数据 loopstart 与常量一致" % id)
	_ok(String(stream.tags.get("looplength", "")) == str(end_frame - start_frame),
		"%s: 元数据 looplength 与 LOOPEND-LOOPSTART 一致" % id)
	if stream.tags.has("loopend"):
		_ok(String(stream.tags.get("loopend", "")) == str(end_frame),
			"%s: 元数据 loopend 与常量一致" % id)


func _stream_path(stream: AudioStream) -> String:
	return String(stream.resource_path) if stream != null else ""


## 起回环探针：新实例流上合成 offset=1.0s、终点 2.0s（bpm=60、beat_count=2）
func _start_probe() -> void:
	if _phase == 2:
		return
	var s := AudioStreamOggVorbis.load_from_file("res://sounds/title.ogg")
	_ok(s != null, "load_from_file 新流实例（回环探针）")
	if s == null:
		_phase = 2
		return
	s.loop = true
	s.loop_offset = 1.0
	s.bpm = 60.0
	s.beat_count = 2
	_probe = AudioStreamPlayer.new()
	_probe.stream = s
	_probe.volume_db = -80.0 # 无声播放，只观测位置
	root.add_child(_probe)
	_probe.play()
	_start_ms = Time.get_ticks_msec()


func _poll_probe() -> void:
	var pos := _probe.get_playback_position()
	if pos < _prev_pos - 0.1:
		_wrapped = true
	_prev_pos = pos
	if _wrapped or Time.get_ticks_msec() - _start_ms > 6500:
		_ok(_wrapped, "6.5s 内观测到位置回跳（loop 生效：2.0s → 1.0s）")
		_probe.stop()
		_probe.queue_free()
		_phase = 2
