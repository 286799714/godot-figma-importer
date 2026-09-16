shader_type canvas_item;
render_mode unshaded;

uniform sampler2D gradient_texture : source_color, filter_linear, repeat_disable;
uniform vec2 label_size = vec2(1.0);
varying vec2 label_uv;
varying vec4 glyph_color;

void vertex() {
    // Font UV addresses the glyph atlas; gradients need the label's local coordinates.
    label_uv = VERTEX / max(label_size, vec2(1.0));
    glyph_color = COLOR;
}

void fragment() {
    // Gradient glyphs are white. Preserve the independently colored text outline.
    if (distance(glyph_color.rgb, vec3(1.0)) < 0.001) {
        vec4 gradient = texture(gradient_texture, label_uv);
        COLOR.rgb = gradient.rgb;
        COLOR.a *= gradient.a;
    }
}
