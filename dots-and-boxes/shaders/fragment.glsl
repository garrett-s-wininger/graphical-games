#version 410 core

// NOTE(garrett): The following color will be the rendered result to the user
out vec4 fragmentColor;

void main() {
    // NOTE(garrett): We normally get [0, -1] from the coordinate, map this to [-1, 1],
    // gl_PointCoord is only available with point primitives so we can't use this
    // shader with other data types
    vec2 coord = 2.0f * gl_PointCoord - 1.0;

    // NOTE(garrett): Using the vector length from the point center, step the alpha
    // across the edge to provide for a smooth blend so our points render as smooth
    // circles
    float distance = length(coord);
    float edge = 0.15;
    float alpha = smoothstep(1.0f, 1.0f - edge, distance);

    // NOTE(garrett): The resulting alpha will only properly blend if we've enabled
    // it externally via OpenGL's glEnable and glBlendFunc calls
    fragmentColor = vec4(0.0f, 0.0f, 0.0f, alpha);
}
