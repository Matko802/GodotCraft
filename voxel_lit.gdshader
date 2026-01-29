shader_type spatial;

uniform sampler2D top_texture : source_color, filter_nearest;
uniform sampler2D side_texture : source_color, filter_nearest;
uniform sampler2D bottom_texture : source_color, filter_nearest;

void fragment() {
    vec3 normal = NORMAL;
    vec4 tex;
    if (normal.y > 0.5) {
        tex = texture(top_texture, UV);
    } else if (normal.y < -0.5) {
        tex = texture(bottom_texture, UV);
    } else {
        tex = texture(side_texture, UV);
    }
    ALBEDO = tex.rgb;
    ALPHA = tex.a;
}
