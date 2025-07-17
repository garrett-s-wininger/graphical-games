package main

import "base:runtime"
import "core:container/small_array"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strconv"

// NOTE(garrett): These constants for window sizing/configuration
BASE_WINDOW_SIZE :: 256
BORDER_SIZE_PX :: 64
MAX_POINT_COUNT :: 5
MAX_POINT_STORAGE :: (MAX_POINT_COUNT + 1) * (MAX_POINT_COUNT + 1)
POINT_SIZE :: 25

// NOTE(garrett): These constants to determine which version of OpenGL to
// target for rendering
OPENGL_MAJOR_TARGET :: 4
OPENGL_MINOR_TARGET :: 1

// NOTE(garrett): These type definitions are meant to hold the actual
// types that we'll use within our game
Point2D :: distinct [2]f32
Color :: distinct [3]f32

// NOTE(garrett): Theming
PLAYER1_COLOR :: Color{1.0, 0.0, 0.0}
UNSELECTED_COLOR :: Color{0.0, 0.0, 0.0}

// NOTE(garrett): These are the global pieces we need to access per-frame for
// proper operation
line_start_idx: Maybe(int) = nil
point_renderer: PointRenderer
point_storage: small_array.Small_Array(MAX_POINT_STORAGE, Point2D)
point_color_storage: small_array.Small_Array(MAX_POINT_STORAGE, Color)

populate_point_verts :: proc(boxes_per_side, window_size: int) {
	ndc_start_offset := 1 - (2 * (f32(BORDER_SIZE_PX) / f32(window_size)))
	point_gap_multiplier := 1.0 / f32(boxes_per_side)
	point_gap := point_gap_multiplier * 2 * ndc_start_offset

	for row := 0; row < boxes_per_side + 1; row += 1 {
		point_y := ndc_start_offset - (f32(row) * point_gap)

		for column := 0; column < boxes_per_side + 1; column += 1 {
			point_x := -ndc_start_offset + (f32(column) * point_gap)
			small_array.push_back(&point_storage, Point2D{point_x, point_y})
			small_array.push_back(&point_color_storage, UNSELECTED_COLOR)
		}
	}
}

is_point_clicked :: proc(
		window: GameWindow,
		mouse_position: Point2D,
		points: []Point2D) -> (int, bool) {
	// NOTE(garrett): Our position is initially between [0, FB Width/Height],
	// we map this to [0, 1], and then convert to [-1, 1] so we use the same
	// coordinate system as our point verticies
	mouse_ndc := Point2D{
		(mouse_position.x / f32(window.framebuffer_width) * 2.0) - 1.0,
		(mouse_position.y / f32(window.framebuffer_height) * 2.0) - 1.0
	}

	// NOTE(garrett): The point size is in pixels before scaling occurs -
	// we need to scale up the size and then cut in half due to it
	// being the side of a square area, rather than radius of a circle -
	// NOTE(garrett): The 1/2 FB Width/Height division here ensures we're
	// properly mapped into an NDC distance
	collision_distance_ndc :=
		((POINT_SIZE * window.dpi_scale) / 2.0) / (f32(window.framebuffer_width) / 2.0)

	// NOTE(garrett): Take the square here as it saves the square root calculaton
	// when comparing against the vertex distance
	collision_distance_squared := collision_distance_ndc * collision_distance_ndc

	check_idx := 0

	// TODO(garrett): We're doing a naive check of all points because the amount is
	// so small but realistically, knowing the NDC quadrant allows us to discard a
	// significant number of point checks on larger boards
	for vert in points {
		distance_vector := mouse_ndc - vert

		// NOTE(garrett): Though it's logical to compare square roots, it's
		// pretty expensive to compute so we leave it as-is for our comparison
		// as the math works out the same so long as both sides are squared
		distance_squared :=
			(distance_vector.x * distance_vector.x) +
			(distance_vector.y * distance_vector.y)

		if collision_distance_squared >= distance_squared {
			return check_idx, true
		}

		check_idx += 1
	}

	return 0, false
}

on_tick :: proc(window: GameWindow, user_inputs: InputState) {
	mouse_position := get_dpi_aware_mouse_position(window)
	point_vertex_data := small_array.slice(&point_storage)
	point_color_data := small_array.slice(&point_color_storage)

	render_data := RenderInfo{
		mouse_position,
		POINT_SIZE,
		// NOTE(garrett): We could also do width - we have a square area so this
		// doesn't matter for our particular use case
		window.framebuffer_height,
		window.dpi_scale,
		i32(len(point_vertex_data)),
		point_color_data
	}

	if user_inputs.lmb_pressed {
		point_idx, is_clicked := is_point_clicked(window, mouse_position, point_vertex_data)

		if is_clicked {
			selected_idx, is_selected := line_start_idx.?

			if !is_selected {
				// NOTE(garrett): In this case, we don't have any selections, track the
				// start of our line
				// TODO(garrett): Validate that point can have new lines created
				small_array.set(&point_color_storage, point_idx, PLAYER1_COLOR)
				line_start_idx = point_idx
			} else {
				if selected_idx == point_idx {
					// NOTE(garrett): We've selected the start of our line again, toggle
					// off our selection
					small_array.set(&point_color_storage, point_idx, UNSELECTED_COLOR)
					line_start_idx = nil
				} else {
					// TODO(garrett): Validate points are adjacent
					// TODO(garrett): Handle line creation between two points
					// TODO(garrett): Switch players
					// TODO(garrett): Box creation
				}
			}
		}
	}

	render(point_renderer, render_data)
}

print_usage :: proc() {
	fmt.eprintln("Usage: dots-and-boxes")
	fmt.eprintln("       dots-and-boxes -s [1,5]")
}

parse_program_args :: proc(program_args: []cstring) -> (int, bool) {
	arg_count := len(program_args)

	if arg_count != 1 && arg_count != 3 {
		print_usage()
		os.exit(1)
	}

	boxes_per_side := 2
	user_provided_sizing : Maybe(string) = nil

	if arg_count == 3 {
		if program_args[1] != "-s" {
			return 0, false
		}

		user_provided_sizing = string(program_args[2])
	}

	sizing, ok := user_provided_sizing.?

	if ok {
		box_sizing_request := strconv.atoi(sizing)

		if box_sizing_request <= 0 || box_sizing_request > MAX_POINT_COUNT {
			return 0, false
		}

		boxes_per_side = box_sizing_request
	}

	return boxes_per_side, true
}

main :: proc() {
	boxes_per_side: int
	ok: bool
	window: GameWindow

	boxes_per_side, ok = parse_program_args(runtime.args__)

	if !ok {
		print_usage()
		os.exit(1)
	}

	logger := log.create_console_logger()
	context.logger = logger

	window_size := BASE_WINDOW_SIZE + (128 * (boxes_per_side - 1))
	populate_point_verts(boxes_per_side, window_size)

	window, ok = create_application_window(
		"Dots-and-Boxes",
		window_size,
		window_size
	)

	if !ok {
		log.fatal("Failed to initialize application windowing")
		os.exit(1)
	}

	defer teardown_windowing_system(window)

	point_renderer, ok = initialize_rendering_backend(
		window.framebuffer_width,
		window.framebuffer_height,
		small_array.slice(&point_storage)
	)

	if !ok {
		log.fatal("Failed to initialize rendering backend")
		os.exit(1)
	}

	defer teardown_rendering_backend(point_renderer)
	run_main_window_loop(window, on_tick)
}
