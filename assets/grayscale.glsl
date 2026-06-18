#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

out vec4 finalColor;

void main() {
    vec4 c = texture(texture0, fragTexCoord) * fragColor * colDiffuse;
    float gray = dot(c.rgb, vec3(0.299, 0.587, 0.114));
    finalColor = vec4(gray, gray, gray, c.a);
}
