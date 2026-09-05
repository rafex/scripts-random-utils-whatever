#version 330

in vec2 texcoord;
uniform sampler2D tex;

vec4 window_shader() {
    vec2 texsize = textureSize(tex, 0);
    vec4 color = texture2D(tex, texcoord / texsize, 0);
    float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 warm = color.rgb * vec3(1.012, 1.000, 0.985);
    warm = mix(vec3(luminance), warm, 1.04);
    color.rgb = clamp(mix(color.rgb, warm, 0.14), 0.0, 1.0);
    return default_post_processing(color);
}
