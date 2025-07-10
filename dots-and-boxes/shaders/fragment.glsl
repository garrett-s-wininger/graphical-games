#version 410 core

// NOTE(garrett): External inputs to help ensure we properly handle screen
// resolution, desired rendering size, and cursor proximity calculations
uniform float dpiScale;
uniform int pointSize;
uniform vec2 mousePosition;

// NOTE(garrett): Center of the point being rendered, passed from vertex shader
in vec2 pointCenter;

// NOTE(garrett): The following color will be the result rendered
out vec4 fragmentColor;

void main() {
    // NOTE(garrett): We normally get [0, -1] from the coordinate, map this to [-1, 1],
    // gl_PointCoord is only available with point primitives so we can't use this
    // shader with other data types
    vec2 coord = 2.0f * gl_PointCoord - 1.0;

    // NOTE(garrett): Using the vector length from the point center, step the alpha
    // across the edge to provide for a smooth blend so our points render as smooth
    // circles
    float distanceFromCenter = length(coord);
    float edge = 0.15;
    float alpha = smoothstep(1.0f, 1.0f - edge, distanceFromCenter);

    vec3 color = vec3(0.0f, 0.0f, 0.0f);

    // TODO(garrett): We'll want to adjust this radius to meet our cutoff
    // and adjust the effect to our liking
    if (distance(mousePosition, pointCenter) < (pointSize * dpiScale)) {
        color = vec3(1.0f, 0.0f, 0.0f);
    }

    // NOTE(garrett): The resulting alpha will only properly blend if we've enabled
    // it externally via OpenGL's glEnable and glBlendFunc calls
    fragmentColor = vec4(color, alpha);
}
