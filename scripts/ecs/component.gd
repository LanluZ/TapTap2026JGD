class_name Component
extends RefCounted
## 组件基类（架构文档 §3）：纯数据 RefCounted 子类，无行为、不引用 Node。
## 每个组件子类声明 class_name；World 以「脚本全局类名」作为组件类型键。


## 返回组件类型键：优先脚本全局类名（class_name），退化为文件名。
## 注意：依赖脚本自身解析出的 class_name，不依赖编辑器扫描缓存。
static func type_of(c: Component) -> StringName:
	if c == null:
		return &""
	var s: Script = c.get_script()
	if s == null:
		return &""
	var gn: StringName = s.get_global_name()
	if gn != &"":
		return gn
	return StringName(String(s.resource_path).get_file().get_basename())
