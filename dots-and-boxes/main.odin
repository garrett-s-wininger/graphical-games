package main

import "core:log"
import "core:os"

// NOTE(garrett): These constants for window sizing/configuration
BASE_WINDOW_SIZE :: 256
BORDER_SIZE_PX :: 64
WINDOW_SIZE :: BASE_WINDOW_SIZE + (128 * (BOX_COUNT - 1))

// TODO(garrett): We should have this as a parameter to the application
// or as a controllable UI element, TBD
BOX_COUNT :: 2
POINT_COUNT :: (BOX_COUNT + 1) * (BOX_COUNT + 1)
POINT_SIZE :: 25

// NOTE(garrett): These constants to determine which version of OpenGL to
// target for rendering
OPENGL_MAJOR_TARGET :: 4
OPENGL_MINOR_TARGET :: 1

Point2D :: distinct [2]f32

// NOTE(garrett): These are the global pieces we need to access per-frame for
// proper operation
point_renderer: PointRenderer
point_storage := [POINT_COUNT]Point2D{}

populate_point_verts :: proc(vert_storage: []Point2D) {
	NDC_DIFFERENCE :: NDC_START_OFFSET - (-NDC_START_OFFSET)
	NDC_START_OFFSET :: 1 - (2 * (f32(BORDER_SIZE_PX) / f32(WINDOW_SIZE)))
	POINT_GAP_MULTIPLIER :: 1.0 / BOX_COUNT
	POINT_GAP :: POINT_GAP_MULTIPLIER * NDC_DIFFERENCE

	vert_idx := 0

	for row := 0; row < BOX_COUNT + 1; row += 1 {
		point_y := NDC_START_OFFSET - (f32(row) * POINT_GAP)

		for column := 0; column < BOX_COUNT + 1; column += 1 {
			point_x := -NDC_START_OFFSET + (f32(column) * POINT_GAP)
			vert_storage[vert_idx] = Point2D{point_x, point_y}
			vert_idx += 1
		}
	}
}

on_tick :: proc(window: GameWindow, user_inputs: InputState) {
	render_data := RenderInfo{
		get_dpi_aware_mouse_position(window),
		POINT_SIZE,
		// NOTE(garrett): We could also do width - we have a square area so this
		// doesn't matter for our particular use case
		window.framebuffer_height,
		window.dpi_scale,
		point_storage[:]
	}

	if user_inputs.lmb_pressed {
		log.info("Pressed mouse button!")
	}

	render(point_renderer, render_data)
}

main :: proc() {
	ok: bool
	window: GameWindow

	logger := log.create_console_logger()
	context.logger = logger

	populate_point_verts(point_storage[:])

	window, ok = create_application_window(
		"Dots-and-Boxes",
		WINDOW_SIZE,
		WINDOW_SIZE
	)

	if !ok {
		log.fatal("Failed to initialize application windowing")
		os.exit(1)
	}

	defer teardown_windowing_system(window)

	point_renderer, ok = initialize_rendering_backend(
		window.framebuffer_width,
		window.framebuffer_height
	)

	if !ok {
		log.fatal("Failed to initialize rendering backend")
		os.exit(1)
	}

	defer teardown_rendering_backend(point_renderer)
	run_main_window_loop(window, on_tick)
}
