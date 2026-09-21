#version 330

// Depth pre-pass para el shadow map — ver Shadow_Map en rendering.odin.
// Locations explícitas por el mismo motivo que lighting.vs: los draws en
// modo inmediato de rlgl (DrawCube/DrawCylinder/...) escriben por posición
// fija, no por nombre.
layout(location = 0) in vec3 vertexPosition;
layout(location = 1) in vec2 vertexTexCoord;
layout(location = 2) in vec3 vertexNormal;
layout(location = 3) in vec4 vertexColor;

// raylib alimenta esto solo con cualquier shader que declare un uniform
// llamado "mvp" mientras esté activo vía BeginShaderMode — siempre que
// rlgl.SetMatrixProjection/SetMatrixModelview ya tengan la luz seteada
// antes del draw (ver render_shadow_depth_pass). Mismo mecanismo del que
// ya depende lighting.vs para la cámara real del jugador.
uniform mat4 mvp;

void main() {
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
