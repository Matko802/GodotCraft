shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_nearest;

void fragment() {
    vec4 tex = texture(albedo_texture, UV);
    ALBEDO = tex.rgb;
    ALPHA = tex.a;
}
