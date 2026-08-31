#version 330

// Locations explícitas — obligatorio para que el modo inmediato de rlgl
// (DrawCube/DrawCylinder/DrawSphere de torres, árboles, obstáculos, ...)
// alimente los atributos correctos: ese camino escribe por posición fija
// (0/1/2/3), sin consultar el shader por nombre como sí hace DrawModel/
// DrawMesh con la malla del terreno. Sin esto, el compilador puede asignarle
// a vertexNormal una location distinta a la 2 y el shader termina leyendo
// datos que no son la normal — se traduce en "sin iluminación" (plano) en
// formas dibujadas en modo inmediato.
layout(location = 0) in vec3 vertexPosition;
layout(location = 1) in vec2 vertexTexCoord;
layout(location = 2) in vec3 vertexNormal;
layout(location = 3) in vec4 vertexColor;

uniform mat4 mvp;

out vec3 fragNormal;
out vec4 fragColor;
out vec2 fragTexCoord;

// Todo lo que este proyecto dibuja en 3D ya está en coordenadas de mundo
// absolutas — no hay una matriz de modelo por objeto ni rotación vía la pila
// de rlgl (ni la malla de terreno ni las formas inmediatas de torres/
// enemigos la usan), así que vertexPosition/vertexNormal ya son world-space
// y no hace falta matModel/matNormal.
void main() {
    fragNormal = normalize(vertexNormal);
    fragColor = vertexColor;
    fragTexCoord = vertexTexCoord;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
