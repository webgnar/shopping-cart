shader_type canvas_item;
// The wearing surface of the asphalt lab (scenes/asphalt/asphalt_lab.tscn), drawn on a ColorRect that covers the
// road section; AsphaltCanvas sets the state uniforms each year. UV 0..1 spans size_m metres.
// Colour: binder that oxidises from black to grey, aggregate that shows through and then ravels out, darker tyre
// polish in the wheel paths and oil drips down the middle of each lane. Height (height_mode): 0.5 = design level,
// 0.1 m to white or black; stones, ravelling pits and wheel-path ruts.

uniform bool height_mode = false;
uniform vec2 size_m = vec2(10.0, 10.0);
uniform float surface_age = 0.0;
uniform float ravel = 0.0;          // 0..1 how far the surface has ravelled
uniform float rut_depth = 0.0;      // m
uniform float chip_seal = 0.0;      // 1 = sprayed seal with a single layer of chips
uniform vec4 wheel_paths = vec4(1.95, 3.75, 6.25, 8.05);
uniform float lane_joint = 5.0;
uniform float shoulder = 0.7;
uniform float seed = 0.0;
uniform float age_scale = 6.0;      // years for the binder to go most of the way to grey
uniform vec3 fresh_color : source_color = vec3(0.075, 0.075, 0.08);
uniform vec3 aged_color : source_color = vec3(0.37, 0.365, 0.35);
uniform vec3 stone_color : source_color = vec3(0.50, 0.49, 0.46);
uniform vec3 chip_color : source_color = vec3(0.46, 0.44, 0.40);
uniform sampler2D chip_texture : source_color, repeat_enable, filter_linear_mipmap;  // chip seal photo, seamless
uniform float chip_texture_m = 1.0;  // m the chip texture spans
uniform bool use_chip_texture = true;
uniform sampler2D fresh_texture : source_color, repeat_enable, filter_linear_mipmap;  // fresh rolled hot mix, seamless
uniform float fresh_texture_m = 1.0;
uniform bool use_fresh_texture = true;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1, 0)), f.x), mix(hash1(i + vec2(0, 1)), hash1(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

// Distance to the nearest stone centre (in cell units) and a random id for it.
vec2 stones(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g);
			float d = length(g + o * 0.8 + 0.1 - f);
			if (d < best) {
				best = d;
				id = hash1(i + g + 0.37);
			}
		}
	}
	return vec2(best, id);
}

float band(float x, float c, float w) {
	return exp(-pow((x - c) / w, 2.0));
}

void fragment() {
	vec2 m = UV * size_m;
	vec2 sp = m + vec2(seed * 1.3, seed * 0.7);
	float ox = 1.0 - exp(-surface_age / age_scale);

	float wheel = band(m.x, wheel_paths.x, 0.28) + band(m.x, wheel_paths.y, 0.28)
		+ band(m.x, wheel_paths.z, 0.28) + band(m.x, wheel_paths.w, 0.28);
	float lane_mid = band(m.x, (wheel_paths.x + wheel_paths.y) * 0.5, 0.35)
		+ band(m.x, (wheel_paths.z + wheel_paths.w) * 0.5, 0.35);

	// Aggregate: 1-2 cm stones (chip seal: one even layer of bigger chips).
	float cells = mix(70.0, 48.0, chip_seal);
	vec2 st = stones(sp * cells);
	float stone_r = mix(0.42, 0.55, chip_seal) * (0.75 + 0.5 * st.y);
	float stone = smoothstep(stone_r, stone_r - 0.12, st.x);
	// Fines between the stones.
	float fines = vnoise(sp * 260.0);
	// Ravelling: stones pluck out, more in the wheel paths and as the surface gets older.
	float rv = ravel * (0.6 + 0.6 * wheel) * (0.7 + 0.6 * fbm(sp * 1.5));
	float pit = step(st.y, rv * 0.45) * stone;
	float mottle = fbm(sp * 0.8) - 0.5;

	if (height_mode) {
		float h = 0.0;
		h += stone * mix(0.0008, 0.002, max(ox, chip_seal)) - pit * 0.004 + (fines - 0.5) * 0.0006;
		h -= rut_depth * (band(m.x, wheel_paths.x, 0.35) + band(m.x, wheel_paths.y, 0.35)
			+ band(m.x, wheel_paths.z, 0.35) + band(m.x, wheel_paths.w, 0.35));
		float v = clamp(0.5 + h / 0.2, 0.0, 1.0);
		COLOR = vec4(vec3(v), 1.0);
	} else {
		vec3 binder = mix(fresh_color, aged_color, ox) * (1.0 + mottle * 0.18) * (0.92 + 0.16 * fines);
		// Stones show more once the binder film wears off them.
		float show = mix(0.08 + 0.45 * ox + 0.4 * ravel, 0.7 + 0.2 * ox, chip_seal);
		vec3 rock = mix(stone_color, chip_color, chip_seal) * (0.8 + 0.4 * st.y);
		vec3 col = mix(binder, mix(binder, rock, show), stone);
		col = mix(col, binder * 0.55, pit);
		if (use_fresh_texture && chip_seal < 1.0) {
			// A new hot-mix surface (or overlay): the rolled mix photo, fading into the procedural surface as the
			// binder greys and the stones show.
			vec3 fresh = texture(fresh_texture, sp / fresh_texture_m).rgb;
			col = mix(col, fresh * (1.0 + mottle * 0.12), pow(1.0 - ox, 1.5) * 0.85 * (1.0 - chip_seal));
		}
		if (use_chip_texture && chip_seal > 0.0) {
			// The chip seal photo, its binder dulling towards grey with age as the chips wear clean.
			vec3 chip = texture(chip_texture, sp / chip_texture_m).rgb;
			chip = mix(chip, aged_color * (0.7 + 0.6 * chip), ox * 0.5);
			col = mix(col, chip, chip_seal);
		}
		// Tyre polish and rubber in the wheel paths; oil and fuel drips down the middle of the lane.
		col *= 1.0 - 0.10 * clamp(wheel, 0.0, 1.0) * min(surface_age / 3.0, 1.0);
		float oil = smoothstep(0.6, 0.78, fbm(sp * vec2(3.5, 1.2) + 11.0) + 0.25 * vnoise(sp * 9.0) - 0.12) * lane_mid * min(surface_age / 4.0, 1.0);
		col = mix(col, col * vec3(0.62, 0.6, 0.57), oil * 0.6);
		COLOR = vec4(col, 1.0);
	}
}
