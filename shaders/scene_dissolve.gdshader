shader_type canvas_item;
render_mode blend_mix, unshaded;

// 全局溶解转场（autoload SceneTransition 的全屏 ColorRect 用）：
// progress 0→1 溶解盖屏 → 切场景 → 1→0 反向揭开。噪声风格与 logo_gloss_dissolve 同源
// （3 倍频 fbm + 暖橙燃边），溶解线随时间缓慢漂移，像烧穿的纸边扫过整屏。
// ColorRect 无贴图，COLOR 输出直接覆盖（顶点色恒白，不依赖 COLOR 输入）。

uniform float progress : hint_range(0.0, 1.0) = 0.0;       // 0 = 全透明，1 = 全覆盖
uniform float noise_scale : hint_range(1.0, 40.0) = 12.0;  // 噪声密度（越大溶解碎块越细）
uniform float edge_width : hint_range(0.005, 0.3) = 0.08;  // 溶解线羽化半宽
uniform vec4 cover_color : source_color = vec4(0.05, 0.06, 0.11, 1.0); // 覆盖层底色（近黑蓝）
uniform vec4 burn_color : source_color = vec4(1.0, 0.62, 0.28, 1.0);   // 燃边暖色（与 LOGO 一致）
uniform float burn_strength : hint_range(0.0, 2.0) = 1.0;  // 燃边亮度
uniform float drift_speed : hint_range(0.0, 1.0) = 0.08;   // 噪声漂移速度（溶解线蠕动感）


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 3 倍频 fbm，值域大致 0..1（均值 ~0.5）
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += vnoise(p) * amp;
		p = p * 2.07 + vec2(13.0, 27.0);
		amp *= 0.5;
	}
	return v / 0.875;
}


void fragment() {
	float n = fbm(UV * noise_scale + vec2(TIME, -TIME * 0.7) * drift_speed);

	// 阈值从 -edge 扫到 1+edge：progress=0 时 n>=0 全在阈值右侧（全透明），
	// progress=1 时 n<=1 全在左侧（全覆盖）。
	float w = max(edge_width, 0.001);
	float thr = progress * (1.0 + 2.0 * w) - w;
	float cover = 1.0 - smoothstep(thr - w, thr + w, n);

	// 燃边：溶解线两侧的暖色亮带，随 progress 扫过整屏
	float rim = (1.0 - smoothstep(0.0, w * 1.5, abs(n - thr))) * burn_strength;

	vec3 col = mix(cover_color.rgb, burn_color.rgb, clamp(rim, 0.0, 1.0));
	col += burn_color.rgb * rim * 0.3;

	COLOR = vec4(col, cover * cover_color.a);
}
