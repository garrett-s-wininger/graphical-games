#version 410 core

// NOTE(garrett): The following are external inputs to ensure we
// can properly provide display independent renders as well as
// provide data to trigger effects on points
uniform int framebufferSize;
uniform float dpiScale;
uniform int pointSize;

// NOTE(garrett): Point verticies provided by our VAO, VBO combo
layout (location = 0) in vec2 position;
layout (location = 1) in vec3 color;

// NOTE(garrett): We'll send the point's center data down to the fragment
// stage so that we can alter coloring/effects for all rasterized point
// pixels
out vec2 pointCenter;

// NOTE(garrett): Though we'll take in the desired color here from the
// game state, we'll pass it on without modification over to the fragment
// shader for colorign decisions
out vec3 desiredColor;

void main() {
    // NOTE(garrett): Positions themselves are unchanged, though point size
    // is multiplied by the pixel scale to ensure we remain consistent
    // across different display types
    gl_Position = vec4(position, 0.0f, 1.0f);
    gl_PointSize = pointSize * dpiScale;

    // NOTE(garrett): We provide our verts in normalized coordinates, need
    // to adjust them back to framebuffer pixels for proper calculations in
    // the fragment shader
    pointCenter = (position * 0.5 + 0.5) * framebufferSize;

    // NOTE(garrett): Straight pass-through as the color is only applicable
    // to the fragment shader
    desiredColor = color;
}
