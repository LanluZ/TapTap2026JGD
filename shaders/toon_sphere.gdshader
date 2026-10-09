shader_type spatial;
render_mode unshaded;

// 主菜单球三渲二（经典赛璐璐）：NdotL 量化 3 色阶 + 硬高光点 + 边缘光，不接场景光照。
// 光向锁定视口（菜单固定机位下无感）；若需世界锁定/接场景灯光，升级路径：去掉 unshaded 改用 light()。

uniform vec3 base_color : source_color = vec3(1.0, 0.55, 0.28);
uniform vec3 shadow_color : source_color = vec3(0.48, 0.17, 0.30);
uniform vec3 highlight_color : source_color = vec3(1.0, 0.83, 0.55);
uniform vec3 spec_color : source_color = vec3(1.0, 0.96, 0.88);
uniform vec3 rim_color : source_color = vec3(1.0, 0.62, 0.42);

// 视口空间，指向光源（左上前方）
uniform vec3 light_dir = vec3(-0.5, 0.7, 0.5);

uniform float shadow_threshold : hint_range(-1.0, 1.0) = 0.15;
uniform float highlight_threshold : hint_range(-1.0, 1.0) = 0.8;
uniform float band_softness : hint_range(0.001, 0.3) = 0.03;
uniform float spec_size : hint_range(0.01, 0.5) = 0.06;
uniform float spec_strength : hint_range(0.0, 1.0) = 0.9;
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.62;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 l = normalize(light_dir);
	vec3 v = normalize(VIEW);

	float ndl = dot(n, l);

	// 3 色阶：阴影 → 基色 → 高光阶
	float lit = smoothstep(shadow_threshold - band_softness, shadow_threshold + band_softness, ndl);
	float hi = smoothstep(highlight_threshold - band_softness, highlight_threshold + band_softness, ndl);
	vec3 col = mix(shadow_color, base_color, lit);
	col = mix(col, highlight_color, hi);

	// 硬边高光点
	float ndh = clamp(dot(n, normalize(l + v)), 0.0, 1.0);
	float spec = smoothstep(1.0 - spec_size, 1.0 - spec_size + band_softness, ndh);
	col = mix(col, spec_color, spec * spec_strength);

	// 边缘光（fresnel）
	float fres = 1.0 - clamp(dot(n, v), 0.0, 1.0);
	float rim = smoothstep(rim_threshold, rim_threshold + band_softness * 2.0, fres);
	col = mix(col, rim_color, rim * rim_strength);

	ALBEDO = col;
}
