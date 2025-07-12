package main

import "core:log"
import "core:os"

import "vendor:glfw"

GameWindow :: struct {
	handle: glfw.WindowHandle,
	width: i32,
	height: i32,
	framebuffer_width: i32,
	framebuffer_height: i32,
	dpi_scale: f32
}

InputState :: struct {
	lmb_pressed: bool
}

// NOTE(garrett): We'll keep track of our pressed state and give a snapshot of
// our input state to client game loops for their tick event that they can use
// for game logic
lmb_pressed := false

@(private="file")
@(require_results)
create_glfw_window :: proc(
		title: cstring,
		width: i32,
		height: i32) -> (glfw.WindowHandle, bool) {
	window := glfw.CreateWindow(width, height, title, nil, nil)

	if window == nil {
		return nil, false
	}

	// NOTE(garrett): We need to explicitly make our newly created window the
	// OpenGL rendering context - this app only uses one so we can set it
	// immediately
	glfw.MakeContextCurrent(window)
	return window, true
}

@(require_results)
get_dpi_aware_mouse_position :: proc(window: GameWindow) -> Point2D {
	mouse_x, mouse_y := glfw.GetCursorPos(window.handle)

	return Point2D{
		f32(mouse_x) * window.dpi_scale,
		(f32(window.height) - f32(mouse_y)) * window.dpi_scale
	}
}

@(require_results)
create_application_window :: proc(
		title: cstring,
		width: i32,
		height: i32) -> (GameWindow, bool) {
	if !glfw.Init() {
		log.error("Windowing system initialization failure")
		return GameWindow{}, false
	}

	// TODO(garrett): Support window resizing, requires framebuffer callback
	glfw.WindowHint(glfw.RESIZABLE, false)

	// NOTE(garrett): The following sets us up to load a minimum version that is
	// compatible with our target, in our case the last used one from Apple for
	// compatibility purposes
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, OPENGL_MAJOR_TARGET)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, OPENGL_MINOR_TARGET)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	window, ok := create_glfw_window(title, width, height)

	if !ok {
		log.error("Failed to create window object")
		return GameWindow{}, false
	}

	framebuffer_width, framebuffer_height := glfw.GetFramebufferSize(window)

	// NOTE(garrett): We need to determine the pixel scaling for high resolution
	// displays, such as Retina on MacOS
	scale_x := f32(framebuffer_width) / f32(width)
	scale_y := f32(framebuffer_height) / f32(height)
	dpi_scale := (scale_x + scale_y) / 2

	return GameWindow{
		window,
		width,
		height,
		framebuffer_width,
		framebuffer_height,
		dpi_scale
	}, true
}

run_main_window_loop :: proc(
		window: GameWindow,
		on_tick: proc(GameWindow, InputState)) {
	glfw.SetMouseButtonCallback(
		window.handle,
		proc "c" (handle: glfw.WindowHandle, button, action, mods: i32) {
			if button == glfw.MOUSE_BUTTON_LEFT && action == glfw.PRESS {
				lmb_pressed = true
			}
		}
	)

	for {
		if (glfw.WindowShouldClose(window.handle)) {
			break
		}

		on_tick(
			window,
			InputState{lmb_pressed}
		)

		lmb_pressed = false
		glfw.SwapBuffers(window.handle)
		glfw.PollEvents()
	}
}

teardown_windowing_system :: proc(window: GameWindow) {
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}
