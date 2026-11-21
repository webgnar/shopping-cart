// The parking garage's sky: the same gradient and sun as Godot's ProceduralSkyMaterial (same settings,
// same look), with an optional skyline panorama laid over it by its alpha. The panorama is an
// equirectangular image whose middle faces -Z and whose right quarter faces +X (how Blender renders
// it, see tools/manhattan_skyline.py). Without a panorama this is just the procedural sky.
shader_type sky;

group_uniforms sky;
uniform vec4 sky_top_color : source_color = vec4(0.385, 0.454, 0.55, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.646, 0.656, 0.67, 1.0);
uniform float sky_curve : hint_range(0, 1) = 0.15;
uniform float sky_energy : hint_range(0, 64) = 1.0;
group_uniforms ground;
uniform vec4 ground_bottom_color : source_color = vec4(0.2, 0.169, 0.133, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.646, 0.656, 0.67, 1.0);
uniform float ground_curve : hint_range(0, 1) = 0.02;
group_uniforms sun;
uniform float sun_angle_max_degrees : hint_range(0, 90) = 30.0;
uniform float sun_curve : hint_range(0, 1) = 0.15;
group_uniforms skyline;
/** Equirectangular skyline with a transparent sky. */
uniform sampler2D skyline : source_color, filter_linear_mipmap, repeat_enable;
/** Turns the skyline around the up axis, in degrees. */
uniform float skyline_yaw_degrees = 0.0;
/** Multiplies the skyline's colour (the photos are daylight; tint them to the scene's light). */
uniform vec4 skyline_tint : source_color = vec4(1.0);

void sky() {
	vec3 dir = EYEDIR;
	float v_angle = acos(clamp(dir.y, -1.0, 1.0));
	float c = 1.0 - v_angle / (PI * 0.5);
	vec3 sky = mix(sky_horizon_color.rgb, sky_top_color.rgb, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	sky *= sky_energy;
	if (LIGHT0_ENABLED) {
		float sun_angle = acos(clamp(dot(LIGHT0_DIRECTION, dir), -1.0, 1.0));
		float sun_min = LIGHT0_SIZE * 0.5;
		float sun_max = radians(sun_angle_max_degrees);
		if (sun_angle < sun_min) {
			sky = LIGHT0_COLOR * LIGHT0_ENERGY;
		} else if (sun_angle < sun_max) {
			float c2 = (sun_angle - sun_min) / (sun_max - sun_min);
			sky = mix(LIGHT0_COLOR * LIGHT0_ENERGY, sky, clamp(1.0 - pow(1.0 - c2, 1.0 / sun_curve), 0.0, 1.0));
		}
	}
	float g = (v_angle - PI * 0.5) / (PI * 0.5);
	vec3 ground = mix(ground_horizon_color.rgb, ground_bottom_color.rgb, clamp(1.0 - pow(1.0 - g, 1.0 / ground_curve), 0.0, 1.0));
	vec3 col = mix(ground, sky, step(0.0, dir.y));

	float yaw = radians(skyline_yaw_degrees);
	vec2 uv = vec2(0.5 + (atan(dir.x, -dir.z) - yaw) / TAU, v_angle / PI);
	vec4 city = textureLod(skyline, uv, 0.0);
	COLOR = mix(col, city.rgb * skyline_tint.rgb, city.a);
}
