#version 410 core

// NOTE(garrett): External inputs to help ensure we properly handle screen
// resolution, desired rendering size, and cursor proximity calculations
uniform float dpiScale;
uniform vec2 mousePosition;
uniform int pointSize;

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
    // circles - gives us an alpha in the range of [0, 1] so we need to invert in
    // our output as we want a higher alpha internally
    float distanceFromCenter = length(coord);
    float edge = 0.15;
    float alpha = smoothstep(0.7f, 1.0f - edge, distanceFromCenter);

    // NOTE(garrett): Start with an initial color of black, and apply pixel scaling
    // to calculate the actual radius that a point should render to
    vec3 color = vec3(0.0f, 0.0f, 0.0f);
    float scaledPointRadius = (pointSize * dpiScale) / 2.0f;

    // NOTE(garrett): To get our highlight effect, check if our provided mouse
    // position within the area that the point should take up and then change
    // the color of the dot accordingly (we use a dark-ish grey here)
    if (distance(mousePosition, pointCenter) <= scaledPointRadius) {
        color = vec3(0.3f, 0.3f, 0.3f);
    }

    // NOTE(garrett): The resulting alpha will only properly blend if we've enabled
    // it externally via OpenGL's glEnable and glBlendFunc calls
    fragmentColor = vec4(color, 1 - alpha);
}
