package main

import "core:io"
import "core:log"
import "core:os"

import "vendor:glfw"
import "vendor:opengl"

// NOTE(garrett): These constants control the maximum size of shader text
// we'll compile as well as how large of a log we'll accept when outputting
// compilation errors
MAX_SHADER_LOG_SIZE :: 1024 * 4
MAX_SHADER_SIZE :: 1024 * 64

@(private="file")
@(require_results)
compile_shader :: proc(type: u32, file: string) -> (u32, bool) {
	if type != OpenGL.VERTEX_SHADER && type != OpenGL.FRAGMENT_SHADER {
		log.error("Shader compilation called with an invalid shader type")
		return 0, false
	}

	handle, open_err := os.open(file)

	if open_err != nil {
		log.error("Failed to open shader file located at", file)
		return 0, false
	}

	defer os.close(handle)
	size, seek_err := io.seek(os.stream_from_handle(handle), 0, .End)

	if seek_err != nil {
		log.error("Failed to determine size of", file)
		return 0, false
	}

	if size >= MAX_SHADER_SIZE {
		log.error(
			"Shader file size of",
			size,
			"exceeds maximum of",
			MAX_SHADER_SIZE - 1,
			"for",
			file
		)

		return 0, false
	}

	shader_data := [MAX_SHADER_SIZE]u8{}
	amount_read, read_err := os.read_at(handle, shader_data[:], 0)

	if i64(amount_read) != size || read_err != nil {
		log.error("Failed to read shader data from", file)
		return 0, false
	}

	shader: u32 = ---

	if shader = OpenGL.CreateShader(type); shader == 0 {
		log.error("Failed to create shader object")
		return 0, false
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
		log.error(failure_message)
		return 0, false
	}

	return shader, true
}

@(private="file")
@(require_results)
create_shader_program :: proc(vert_shader_file: string, frag_shader_file: string) -> (u32, bool) {
	ok: bool
	vert_shader: u32
	frag_shader: u32

	// NOTE(garrett): The shader objects for the vertex and fragment shader can be thought of
	// intermediates that aren't necessary after the full shader program is rendered so we
	// can safely have them deleted at the end of the function to free resources
	vert_shader, ok = compile_shader(OpenGL.VERTEX_SHADER, vert_shader_file)

	if !ok {
		log.error("Vertex shader compilation failed")
		return 0, false
	}

	defer OpenGL.DeleteShader(vert_shader)

	frag_shader, ok = compile_shader(OpenGL.FRAGMENT_SHADER, frag_shader_file)

	if !ok {
		log.error("Fragment shader compilation failed")
		return 0, false
	}

	defer OpenGL.DeleteShader(frag_shader)

	shader_program: u32 = ---

	if shader_program = OpenGL.CreateProgram(); shader_program == 0 {
		log.error("Failed to create shader program")
		return 0, false
	}

	OpenGL.AttachShader(shader_program, vert_shader);
	OpenGL.AttachShader(shader_program, frag_shader);
	OpenGL.LinkProgram(shader_program);

	link_status: i32 = ---
	OpenGL.GetProgramiv(shader_program, OpenGL.LINK_STATUS, &link_status)

	if link_status == 0 {
		// TODO(garrett): Retrieve and output program info log
		log.error("Failed to link shader program")
		return 0, false
	}

	return shader_program, true
}

@(private="file")
@(require_results)
prepare_point_buffers :: proc() -> (u32, u32) {
	vao : u32 = ---

	OpenGL.GenVertexArrays(1, &vao)
	OpenGL.BindVertexArray(vao)
	defer OpenGL.BindVertexArray(0)

	vbo: u32 = ---

	OpenGL.GenBuffers(1, &vbo)
	OpenGL.BindBuffer(OpenGL.ARRAY_BUFFER, vbo)
	defer OpenGL.BindBuffer(OpenGL.ARRAY_BUFFER, 0)

	OpenGL.VertexAttribPointer(0, 2, OpenGL.FLOAT, false, 0, 0)

	return vao, vbo
}

PointRenderer :: struct {
	vao: u32,
	vbo: u32,
	shader_program: u32,
	dpi_scale_uniform: i32,
	framebuffer_uniform: i32,
	mouse_position_uniform: i32,
	point_size_uniform: i32,
}

RenderInfo :: struct {
	mouse_position: Point2D,
	point_size: i32,
	framebuffer_size: i32,
	dpi_scale: f32,
	points: []Point2D,
}

@(private="file")
render_points :: proc(renderer: PointRenderer, data: RenderInfo) {
	// NOTE(garrett): We'll first jump to our point shader program
	OpenGL.UseProgram(renderer.shader_program)

	// NOTE(garrett): Now that we have our program, we need to load
	// data into each of the uniform values that we have defined in
	// our vertex and fragment shaders
	OpenGL.Uniform1i(
		renderer.point_size_uniform,
		data.point_size
	)

	OpenGL.Uniform1i(
		renderer.framebuffer_uniform,
		data.framebuffer_size
	)

	OpenGL.Uniform1f(
		renderer.dpi_scale_uniform,
		data.dpi_scale
	)

	OpenGL.Uniform2f(
		renderer.mouse_position_uniform,
		data.mouse_position.x,
		data.mouse_position.y
	)

	// NOTE(garrett): As we may have changing data, bind our
	// vertex data and send it over to the GPU
	OpenGL.BindBuffer(OpenGL.ARRAY_BUFFER, renderer.vbo);
	defer OpenGL.BindBuffer(OpenGL.ARRAY_BUFFER, 0);

	OpenGL.BufferData(
		OpenGL.ARRAY_BUFFER,
		len(data.points) * size_of(Point2D),
		raw_data(data.points),
		OpenGL.STATIC_DRAW
	)

	// NOTE(garrett): The vertex array is what we actually need loaded
	// so ensure it's activated
	OpenGL.BindVertexArray(renderer.vao)
	defer OpenGL.BindVertexArray(0)

	// NOTE(garrett): For our actual rendering, we first need to enable
	// the attributes we intend to use whose numbers are defined in our
	// shader text
	OpenGL.EnableVertexAttribArray(0)
	defer OpenGL.DisableVertexAttribArray(0)

	OpenGL.DrawArrays(OpenGL.POINTS, 0, i32(len(data.points)))
}

render :: proc(renderer: PointRenderer, data: RenderInfo) {
	// NOTE(garrett): Before we do any rendering, clear the entire
	// screen so pixels that are not overwritten do not leave
	// artifacts from the previous frame
	OpenGL.Clear(OpenGL.COLOR_BUFFER_BIT)
	render_points(renderer, data)
}

initialize_rendering_backend :: proc(framebuffer_width, framebuffer_height: i32) -> (PointRenderer, bool) {
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

	point_shader, ok := create_shader_program(
		"shaders/vertex.glsl",
		"shaders/fragment.glsl"
	)

	if !ok {
		log.error("Failed to create point shader program")
		return PointRenderer{}, false
	}

	// NOTE(garrett): We need to query our linked program for where we should
	// put our external data necessary for rendering, this will be loaded into the
	// shader program prior to each render pass
	dpi_scale_uniform := OpenGL.GetUniformLocation(point_shader, "dpiScale")
	framebuffer_uniform := OpenGL.GetUniformLocation(point_shader, "framebufferSize")
	mouse_uniform := OpenGL.GetUniformLocation(point_shader, "mousePosition")
	point_size_uniform := OpenGL.GetUniformLocation(point_shader, "pointSize")

	point_vao, point_vbo := prepare_point_buffers()

	return PointRenderer{
		point_vao,
		point_vbo,
		point_shader,
		dpi_scale_uniform,
		framebuffer_uniform,
		mouse_uniform,
		point_size_uniform
	}, true
}

teardown_rendering_backend :: proc(renderer: PointRenderer) {
	OpenGL.DeleteProgram(renderer.shader_program)
}
