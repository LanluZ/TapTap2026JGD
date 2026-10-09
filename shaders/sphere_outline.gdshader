shader_type spatial;
render_mode unshaded, cull_front;

// 反向壳描边：法线外扩 + 只画背面；球体法线均匀，描边粗细天然一致。

uniform float width : hint_range(0.001, 0.2) = 0.035;
uniform vec3 outline_color : source_color = vec3(0.2, 0.07, 0.06);

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = outline_color;
}
