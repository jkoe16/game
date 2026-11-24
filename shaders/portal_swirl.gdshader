// 포털 안쪽의 소용돌이 (시간에 따라 회전, 가장자리로 갈수록 투명). 모든 렌더러 지원
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.6, 0.8, 1.0);
uniform float speed = 1.6;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = 0.5 + 0.5 * sin(a * 3.0 + r * 9.0 - TIME * speed * 3.0);
	float core = smoothstep(1.0, 0.0, r);
	float edge = smoothstep(1.0, 0.82, r);
	vec3 c = mix(color.rgb, vec3(1.0), swirl * 0.45 + core * core * 0.5);
	ALBEDO = c;
	ALPHA = edge * (0.25 + 0.5 * swirl) * (0.45 + 0.55 * core);
}
