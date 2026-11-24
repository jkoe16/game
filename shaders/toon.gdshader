// 3D PARTY WORLD 공용 카툰 셰이더 (Mobile / Compatibility 렌더러 모두 지원)
// 부드러운 2단 셀 음영 + 파스텔 그림자색 + 은은한 하이라이트 + 림 라이트.
// 텍스처 없이 색상만으로 동작해 모바일 부담이 적다.
shader_type spatial;
render_mode diffuse_lambert;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 shadow_tint : source_color = vec4(0.66, 0.64, 0.95, 1.0);
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.3;
uniform float band_softness : hint_range(0.001, 0.8) = 0.32;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.14;
uniform float gloss : hint_range(0.0, 1.0) = 0.12;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	// 위를 향한 면은 살짝 밝게 (하늘빛 반사) → 통통하고 부드러운 볼륨감
	float sky = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	EMISSION = albedo.rgb * (rim * rim_strength + sky * 0.02);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.05, band_softness, ndl) * ATTENUATION;
	vec3 shade = mix(shadow_tint.rgb * (1.0 - shadow_strength), vec3(1.0), lit);
	DIFFUSE_LIGHT += shade * LIGHT_COLOR / PI;
	// 작고 부드러운 광택점 (플라스틱 장난감 느낌)
	vec3 h = normalize(LIGHT + VIEW);
	float spec = smoothstep(0.92, 0.985, dot(NORMAL, h)) * gloss * ATTENUATION;
	SPECULAR_LIGHT += LIGHT_COLOR * spec;
}
