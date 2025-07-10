package main

import "core:fmt"
import "core:io"
import "core:os"

import "vendor:glfw"
import "vendor:OpenGL"

// NOTE(garrett): These constants for window sizing/configuration
BASE_WINDOW_SIZE :: 256
BORDER_SIZE_PX :: 64
// TODO(garrett): We should have this as a parameter to the application
// or as a controllable UI element, TBD
BOX_COUNT :: 2
NDC_DIFFERENCE :: NDC_START_OFFSET - (-NDC_START_OFFSET)
NDC_START_OFFSET :: 1 - (2 * (f32(BORDER_SIZE_PX) / f32(WINDOW_SIZE)))
POINT_COUNT :: (BOX_COUNT + 1) * (BOX_COUNT + 1)
POINT_GAP_MULTIPLIER :: 1.0 / BOX_COUNT
POINT_GAP :: POINT_GAP_MULTIPLIER * NDC_DIFFERENCE
POINT_SIZE :: 25
PROGRAM :: "Dots-and-Boxes"
WINDOW_SIZE :: BASE_WINDOW_SIZE + (128 * (BOX_COUNT - 1))

// NOTE(garrett): These constants control the maximum size of shader text
// we'll compile as well as how large of a log we'll accept when outputting
// compilation errors
MAX_SHADER_LOG_SIZE :: 1024 * 4
MAX_SHADER_SIZE :: 1024 * 64

// NOTE(garrett): These constants to determine which version of OpenGL to
// target for rendering
OPENGL_MAJOR_TARGET :: 4
OPENGL_MINOR_TARGET :: 1

Point2D :: distinct [2]f32

populate_point_verts :: proc(vert_storage: []Point2D) {
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

init_glfw :: proc() {
	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(1)
	}

	// TODO(garrett): Support window resizing, requires framebuffer callback
	glfw.WindowHint(glfw.RESIZABLE, false)

	// NOTE(garrett): The following sets us up to load a minimum version that is
	// compatible with our target, in our case the last used one from Apple for
	// compatibility purposes
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, OPENGL_MAJOR_TARGET)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, OPENGL_MINOR_TARGET)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
}

@(require_results)
create_glfw_window :: proc() -> glfw.WindowHandle {
	window := glfw.CreateWindow(WINDOW_SIZE, WINDOW_SIZE, PROGRAM, nil, nil)

	if window == nil {
		fmt.eprintln("Unable to create GLFW window")
		os.exit(1)
	}

	// NOTE(garrett): We need to explicitly make our newly created window the OpenGL
	// rendering context - this app only uses one so we can set it immediately
	glfw.MakeContextCurrent(window)
	return window
}

init_opengl :: proc(framebuffer_width, framebuffer_height: i32) {
	// NOTE(garrett): This comes up different ways in different languages but
	// ensures we have our OpenGL functions actually loaded and available
	OpenGL.load_up_to(OPENGL_MAJOR_TARGET, OPENGL_MINOR_TARGET, glfw.gl_set_proc_address)

	// NOTE(garrett): Sets the initial normalized device coordinates (NDC)
	// to match the window, using white as our default background color
	OpenGL.Viewport(0, 0, framebuffer_width, framebuffer_height)
	OpenGL.ClearColor(1.0, 1.0, 1.0, 1.0)

	// NOTE(garrett): This provides us with fragment coordinate data in our shader
	OpenGL.Enable(OpenGL.PROGRAM_POINT_SIZE)

	// NOTE(garrett): The following allow for alpha-blending to support transparency
	OpenGL.Enable(OpenGL.BLEND);
	OpenGL.BlendFunc(OpenGL.SRC_ALPHA, OpenGL.ONE_MINUS_SRC_ALPHA)
}

@(require_results)
compile_shader :: proc(type: u32, file: string) -> u32 {
	if type != OpenGL.VERTEX_SHADER && type != OpenGL.FRAGMENT_SHADER {
		fmt.eprintln("Shader compilation called with an invalid shader type")
		os.exit(1)
	}

	handle, open_err := os.open(file)

	if open_err != nil {
		fmt.eprintln("Failed to open shader file located at", file)
		os.exit(1)
	}

	defer os.close(handle)
	size, seek_err := io.seek(os.stream_from_handle(handle), 0, .End)

	if seek_err != nil {
		fmt.eprintln("Failed to determine size of", file)
		os.exit(1)
	}

	if size >= MAX_SHADER_SIZE {
		fmt.eprintln(
			"Shader file size of",
			size,
			"exceeds maximum of",
			MAX_SHADER_SIZE - 1,
			"for",
			file
		)

		os.exit(1)
	}

	shader_data := [MAX_SHADER_SIZE]u8{}
	amount_read, read_err := os.read_at(handle, shader_data[:], 0)

	if i64(amount_read) != size || read_err != nil {
		fmt.eprintln("Failed to read shader data from", file)
		os.exit(1)
	}

	shader: u32 = ---

	if shader = OpenGL.CreateShader(type); shader == 0 {
		fmt.eprintln("Failed to create shader object")
		os.exit(1)
	}

	shader_source := cstring(&shader_data[0])
	OpenGL.ShaderSource(shader, 1, &shader_source, nil)
	OpenGL.CompileShader(shader)

	compilation_status: i32 = ---
	OpenGL.GetShaderiv(shader, OpenGL.COMPILE_STATUS, &compilation_status)

	if compilation_status == 0 {
		info_log := [MAX_SHADER_LOG_SIZE]u8{}

		OpenGL.GetShaderInfoLog(
			shader,
			MAX_SHADER_LOG_SIZE,
			nil,
			raw_data(info_log[:])
		)

		failure_message := cstring(&info_log[0])
		fmt.println(failure_message)
		os.exit(1)
	}

	return shader
}

@(require_results)
create_shader_program :: proc(vert_shader_file: string, frag_shader_file: string) -> u32 {
	// NOTE(garrett): The shader objects for the vertex and fragment shader can be thought of
	// intermediates that aren't necessary after the full shader program is rendered so we
	// can safely have them deleted at the end of the function to free resources
	vert_shader := compile_shader(OpenGL.VERTEX_SHADER, vert_shader_file)
	defer OpenGL.DeleteShader(vert_shader)

	frag_shader := compile_shader(OpenGL.FRAGMENT_SHADER, frag_shader_file)
	defer OpenGL.DeleteShader(frag_shader)

	shader_program: u32 = ---

	if shader_program = OpenGL.CreateProgram(); shader_program == 0 {
		fmt.eprintln("Failed to create shader program")
		os.exit(1)
	}

	OpenGL.AttachShader(shader_program, vert_shader);
	OpenGL.AttachShader(shader_program, frag_shader);
	OpenGL.LinkProgram(shader_program);

	link_status: i32 = ---
	OpenGL.GetProgramiv(shader_program, OpenGL.LINK_STATUS, &link_status)

	if link_status == 0 {
		// TODO(garrett): Retrieve and output program info log
		fmt.eprintln("Failed to link shader program")
		os.exit(1)
	}

	return shader_program
}

@(require_results)
prepare_point_buffer_vao :: proc(points: []Point2D) -> u32 {
	vao : u32 = ---

	OpenGL.GenVertexArrays(1, &vao)
	OpenGL.BindVertexArray(vao)
	defer OpenGL.BindVertexArray(0)

	vbo: u32 = ---

	OpenGL.GenBuffers(1, &vbo)
	OpenGL.BindBuffer(OpenGL.ARRAY_BUFFER, vbo)
	defer OpenGL.BindBuffer(OpenGL.ARRAY_BUFFER, 0)

	OpenGL.BufferData(
		OpenGL.ARRAY_BUFFER,
		len(points) * size_of(Point2D),
		raw_data(points),
		OpenGL.STATIC_DRAW
	)

	OpenGL.VertexAttribPointer(0, 2, OpenGL.FLOAT, false, 0, 0)

	// NOTE(garrett): This has to match the layout in the shader that we use for points
	OpenGL.EnableVertexAttribArray(0)

	return vao
}

PointRenderData :: struct {
	point_count: i32,
	mouse_position_uniform: i32,
	mouse_position: Point2D,
	framebuffer_uniform: i32,
	framebuffer_size: i32,
	dpi_scale_uniform: i32,
	dpi_scale: f32,
	point_size_uniform: i32,
	point_size: i32
}

render_points :: proc(point_vao: u32, point_shader: u32, render_data: PointRenderData) {
	OpenGL.Clear(OpenGL.COLOR_BUFFER_BIT)

	OpenGL.UseProgram(point_shader)
	OpenGL.BindVertexArray(point_vao)
	defer OpenGL.BindVertexArray(0)

	OpenGL.Uniform1i(
		render_data.point_size_uniform,
		render_data.point_size
	)

	OpenGL.Uniform1i(
		render_data.framebuffer_uniform,
		render_data.framebuffer_size
	)

	OpenGL.Uniform1f(
		render_data.dpi_scale_uniform,
		render_data.dpi_scale
	)

	OpenGL.Uniform2f(
		render_data.mouse_position_uniform,
		render_data.mouse_position.x,
		render_data.mouse_position.y
	)

	OpenGL.DrawArrays(OpenGL.POINTS, 0, render_data.point_count)
}

get_dpi_aware_mouse_position :: proc(window: glfw.WindowHandle, dpi_scale: f32) -> Point2D {
	mouse_x, mouse_y := glfw.GetCursorPos(window)

	return Point2D{
		f32(mouse_x) * dpi_scale,
		(WINDOW_SIZE - f32(mouse_y)) * dpi_scale
	}
}

main :: proc() {
	verts := [POINT_COUNT]Point2D{}
	populate_point_verts(verts[:])

	init_glfw()
	defer glfw.Terminate()

	window := create_glfw_window()
	defer glfw.DestroyWindow(window)

	framebuffer_width, framebuffer_height := glfw.GetFramebufferSize(
		window
	)

	init_opengl(framebuffer_width, framebuffer_height)

	point_vao := prepare_point_buffer_vao(verts[:])
	point_shader := create_shader_program(
		"shaders/vertex.glsl",
		"shaders/fragment.glsl"
	)

	defer OpenGL.DeleteProgram(point_shader)

	// NOTE(garrett): We need to query our linked program for where we should
	// put our external data necessary for rendering, this will be loaded into the
	// shader program prior to each render pass
	framebuffer_uniform := OpenGL.GetUniformLocation(point_shader, "framebufferSize")
	mouse_uniform := OpenGL.GetUniformLocation(point_shader, "mousePosition")
	dpi_scale_uniform := OpenGL.GetUniformLocation(point_shader, "dpiScale")
	point_size_uniform := OpenGL.GetUniformLocation(point_shader, "pointSize")

	// NOTE(garrett): We need to determine the pixel scaling for high resolution
	// displays, such as Retina on MacOS
	scale_x := f32(framebuffer_width) / WINDOW_SIZE
	scale_y := f32(framebuffer_height) / WINDOW_SIZE
	dpi_scale := (scale_x + scale_y) / 2

	for {
		if (glfw.WindowShouldClose(window)) {
			break
		}

		// TODO(garrett): There's likely much better ways to organize the rendering
		// that we'll want to explore, especially as we move to lines and more
		// interactivity
		render_data := PointRenderData{
			i32(len(verts)),
			mouse_uniform,
			get_dpi_aware_mouse_position(window, dpi_scale),
			framebuffer_uniform,
			framebuffer_width,
			dpi_scale_uniform,
			dpi_scale,
			point_size_uniform,
			POINT_SIZE
		}

		render_points(point_vao, point_shader, render_data)

		glfw.SwapBuffers(window)
		glfw.PollEvents()
	}
}
