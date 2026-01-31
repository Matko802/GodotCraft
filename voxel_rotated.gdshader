shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D top_texture : source_color, filter_nearest;
uniform sampler2D side_texture : source_color, filter_nearest;
uniform sampler2D bottom_texture : source_color, filter_nearest;
uniform vec3 up_vector = vec3(0.0, 1.0, 0.0);

varying vec3 v_normal;

void vertex() {
	v_normal = NORMAL;
}

void fragment() {
	// Normalize just in case interpolation affected it
	vec3 n = normalize(v_normal);
	float dot_up = dot(n, up_vector);
	
	vec4 albedo;
	if (dot_up > 0.5) {
		albedo = texture(top_texture, UV);
	} else if (dot_up < -0.5) {
		albedo = texture(bottom_texture, UV);
	} else {
		albedo = texture(side_texture, UV);
	}
	ALBEDO = albedo.rgb;
}
