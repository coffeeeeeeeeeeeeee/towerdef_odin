#version 330

// Iluminación para modelos reales — mismo sol/fill/ambient/sombra que
// lighting.fs (ver shadow_factor ahí), pero sin nada de terreno (sin
// path/agua/dunas/pasto/roca: los árboles no son el terreno). Suma sobre
// eso la textura difusa real que el terreno y las formas inmediatas no
// necesitan (torres/spawn/goal/etc. son color plano por vértice).
in vec3 fragNormal;
in vec2 fragTexCoord;
in vec4 fragColor;
in vec4 fragPosLightSpace;

uniform vec3 sunDir;
uniform vec3 sunColor;
uniform vec3 fillDir;
uniform vec3 fillColor;
uniform vec3 ambient;

uniform sampler2D shadowMap;
uniform float shadowDepthBias;
uniform float shadowMinFactor;

// texture0/colDiffuse: nombres estándar que raylib resuelve solo por
// material (el mapa ALBEDO y su color, ver DrawMesh) — mismo mecanismo por
// el que texture0/texture1 ya se resuelven solos en lighting.fs. Los
// modelos con textura real (pine) traen algo != blanco en texture0; los
// que solo tienen color plano en el .mtl (tree/palm/bush, sin mapa de
// textura) quedan con el 1x1 blanco default de raylib — colDiffuse es lo
// que efectivamente los pinta en ese caso.
uniform sampler2D texture0;
uniform vec4 colDiffuse;

out vec4 finalColor;

// Bias escalado por pendiente — ver la nota larga en lighting.fs
// (shadow_factor ahí). Acá importa TODAVÍA más que en el terreno: la copa
// de un árbol real es geometría angosta y densa (hojas/fronds casi
// coplanares entre sí, muchas casi de canto respecto del sol) — con el
// bias fijo de antes se autosombreaban entre ellas en un patrón rayado
// ("efecto tijera") en vez de un borde de sombra limpio.
float shadow_factor(float ndotl) {
    vec3 proj = fragPosLightSpace.xyz / fragPosLightSpace.w;
    proj = proj * 0.5 + 0.5;
    if (proj.z > 1.0) return 1.0;

    float slope = clamp(sqrt(max(1.0 - ndotl * ndotl, 0.0)) / max(ndotl, 0.05), 0.0, 8.0);
    float bias = max(shadowDepthBias, shadowDepthBias * slope);

    float lit = 0.0;
    vec2 texel = 1.0 / vec2(textureSize(shadowMap, 0));
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            float closest = texture(shadowMap, proj.xy + vec2(x, y) * texel).r;
            lit += (proj.z - bias > closest) ? 0.0 : 1.0;
        }
    }
    lit /= 9.0;
    return mix(shadowMinFactor, 1.0, lit);
}

void main() {
    vec3 n = normalize(fragNormal);
    float sunDiff = max(dot(n, sunDir), 0.0);
    float fillDiff = max(dot(n, fillDir), 0.0);
    float sf = shadow_factor(sunDiff);
    vec3 lit = ambient + sunColor * sunDiff * sf + fillColor * fillDiff;

    vec4 tex = texture(texture0, fragTexCoord);
    vec3 base = tex.rgb * colDiffuse.rgb * fragColor.rgb;

    finalColor = vec4(base * lit, tex.a * colDiffuse.a * fragColor.a);
}
