// 3D PARTY WORLD 공용 카툰 셰이더 (Mobile / Compatibility 렌더러 모두 지원)
// 2단 셀 음영 + 부드러운 림 라이트. 텍스처 없이 색상만으로 동작해 모바일 부담이 적다.
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.66, 0.92, 1.0);
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.35;
uniform float band_softness : hint_range(0.001, 0.5) = 0.06;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.12;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = albedo.rgb * rim * rim_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, band_softness, ndl) * ATTENUATION;
	vec3 shade = mix(shadow_tint.rgb * (1.0 - shadow_strength), vec3(1.0), lit);
	DIFFUSE_LIGHT += shade * LIGHT_COLOR / PI;
}
