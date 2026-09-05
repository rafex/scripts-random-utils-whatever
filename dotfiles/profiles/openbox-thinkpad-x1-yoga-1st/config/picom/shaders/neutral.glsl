#version 330

in vec2 texcoord;
uniform sampler2D tex;

// Shader de recuperación: reproduce el renderizado normal de Picom.
vec4 window_shader() {
    vec2 texsize = textureSize(tex, 0);
    vec4 color = texture2D(tex, texcoord / texsize, 0);
    return default_post_processing(color);
}
