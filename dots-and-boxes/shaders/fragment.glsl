#version 410 core

out vec4 FragColor;

void main() {
    // NOTE(garrett): The below lines clip our normally square points to a cirle to
    // generate a dot
    vec2 circularCoordinate = 2.0f * gl_PointCoord - 1.0;

    if (dot(circularCoordinate, circularCoordinate) > 0.5) {
        // TODO(garrett): This isn't necessarily a fragment shader problem but we'll want
        // a form of anti-aliasing as the current format results in jagged edges
        discard;
    }

    FragColor = vec4(0.0f, 0.0f, 0.0f, 1.0f);
}
