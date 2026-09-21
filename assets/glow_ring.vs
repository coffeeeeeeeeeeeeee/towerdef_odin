#version 330

// Portado desde el viejo assets/glow_circle.glsl (2D, borrado en la
// migración a 3D) — ver render_glow_particles_3d en rendering.odin. Mismas
// locations explícitas que lighting.vs/shadow_depth.vs: draw_glow_ring_3d
// dibuja el quad en modo inmediato de rlgl, que escribe por posición fija.
layout(location = 0) in vec3 vertexPosition;
layout(location = 1) in vec2 vertexTexCoord;
layout(location = 2) in vec3 vertexNormal;
layout(location = 3) in vec4 vertexColor;

uniform mat4 mvp;

out vec2 fragTexCoord;
out vec4 fragColor;

void main() {
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
