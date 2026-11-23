shader_type spatial;
// The Cart Ball's panels: `segments` wedges around its axis in two alternating colours, with caps at both poles,
// laid out in the ball's own space so they turn with it (you can see it spin).

uniform vec4 panel_a : source_color = vec4(1.0, 0.8, 0.12, 1.0);
uniform vec4 panel_b : source_color = vec4(0.95, 0.95, 0.92, 1.0);
uniform vec4 cap_color : source_color = vec4(0.15, 0.17, 0.2, 1.0);
uniform int segments = 6;
uniform float cap_size : hint_range(0.0, 1.0) = 0.9;   // |y| of the normal past which the pole cap starts
uniform float roughness : hint_range(0.0, 1.0) = 0.35;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(local_pos);
	float a = atan(n.z, n.x) / TAU + 0.5;
	float s = floor(a * float(segments));
	vec3 c = mod(s, 2.0) < 1.0 ? panel_a.rgb : panel_b.rgb;
	ALBEDO = abs(n.y) > cap_size ? cap_color.rgb : c;
	ROUGHNESS = roughness;
}
