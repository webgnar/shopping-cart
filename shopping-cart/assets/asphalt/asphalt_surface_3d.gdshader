shader_type spatial;
// The asphalt lab's road section in 3D: a finely subdivided 10 x 10 m plane pushed up and down by
// AsphaltSim.bake_height() (real metres), coloured by the lab's colour map. Normals come from the height map
// (the cracks, holes, ruts and edges) plus a fine bump taken from the colour map's brightness (the stones).

uniform sampler2D albedo_map : source_color, filter_linear_mipmap;
uniform sampler2D height_map : filter_linear;    // FORMAT_RF, metres
uniform vec2 height_texel = vec2(0.001, 0.001);  // one height-map pixel in UV
uniform vec2 size_m = vec2(10.0, 10.0);
uniform float exaggeration = 1.0;                // 1 = real heights
uniform float detail_bump = 0.0015;              // m of bump from the colour map's brightness
uniform float roughness = 0.9;

float h_at(vec2 uv) {
	return textureLod(height_map, uv, 0.0).r * exaggeration;
}

void vertex() {
	VERTEX.y += h_at(UV);
}

void fragment() {
	vec2 t = height_texel;
	float hx = h_at(UV + vec2(t.x, 0.0)) - h_at(UV - vec2(t.x, 0.0));
	float hz = h_at(UV + vec2(0.0, t.y)) - h_at(UV - vec2(0.0, t.y));
	vec2 step_m = 2.0 * t * size_m;
	// Fine bump: brighter colour = stone tops, a little higher.
	vec2 ct = t * 0.5;
	float lx = dot(texture(albedo_map, UV + vec2(ct.x, 0.0)).rgb - texture(albedo_map, UV - vec2(ct.x, 0.0)).rgb, vec3(0.333));
	float lz = dot(texture(albedo_map, UV + vec2(0.0, ct.y)).rgb - texture(albedo_map, UV - vec2(0.0, ct.y)).rgb, vec3(0.333));
	vec3 n = normalize(vec3(-(hx / step_m.x + lx * detail_bump / (step_m.x * 0.5)), 1.0, -(hz / step_m.y + lz * detail_bump / (step_m.y * 0.5))));
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = texture(albedo_map, UV).rgb;
	ROUGHNESS = roughness;
}
