// toon.gdshader 와 같은 음영, 색은 MultiMesh 인스턴스 색(COLOR)을 사용 (꽃밭 등)
shader_type spatial;
render_mode diffuse_lambert;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 shadow_tint : source_color = vec4(0.66, 0.64, 0.95, 1.0);
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.3;
uniform float band_softness : hint_range(0.001, 0.8) = 0.32;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.14;
uniform float gloss : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = albedo.rgb * COLOR.rgb;
	ALBEDO = c;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	EMISSION = c * rim * rim_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.05, band_softness, ndl) * ATTENUATION;
	vec3 shade = mix(shadow_tint.rgb * (1.0 - shadow_strength), vec3(1.0), lit);
	DIFFUSE_LIGHT += shade * LIGHT_COLOR / PI;
}
