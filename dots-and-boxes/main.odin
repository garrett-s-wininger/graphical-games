package main

import "core:fmt"
import "core:io"
import "core:os"

import "vendor:glfw"
import "vendor:OpenGL"

MAX_SHADER_LOG_SIZE :: 1024 * 4
MAX_SHADER_SIZE :: 1024 * 64
OPENGL_MAJOR_TARGET :: 4
OPENGL_MINOR_TARGET :: 1
PROGRAM :: "Dots-and-Boxes"
WINDOW_SIZE :: 256

init_glfw :: proc() {
	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(1)
	}

	// TODO(garrett): Support window resizing, requires framebuffer callback
	glfw.WindowHint(glfw.RESIZABLE, false)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, OPENGL_MAJOR_TARGET)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, OPENGL_MINOR_TARGET)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
}

create_glfw_window :: proc() -> glfw.WindowHandle {
	window := glfw.CreateWindow(WINDOW_SIZE, WINDOW_SIZE, PROGRAM, nil, nil)

	if window == nil {
		fmt.eprintln("Unable to create GLFW window")
		os.exit(1)
	}

	glfw.MakeContextCurrent(window)
	return window
}

init_opengl :: proc() {
	OpenGL.load_up_to(OPENGL_MAJOR_TARGET, OPENGL_MINOR_TARGET, glfw.gl_set_proc_address)
	OpenGL.Viewport(0, 0, WINDOW_SIZE, WINDOW_SIZE)
	OpenGL.ClearColor(1.0, 1.0, 1.0, 1.0)
	OpenGL.Enable(OpenGL.PROGRAM_POINT_SIZE)
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
prepare_point_buffer_vao :: proc() -> u32 {
	vao : u32 = ---

	OpenGL.GenVertexArrays(1, &vao)
	OpenGL.BindVertexArray(vao)
	defer OpenGL.BindVertexArray(0)

	verts := [?]f32{
		0.5, 0.5,
		0.5, -0.5,
		-0.5, 0.5,
		-0.5, -0.5
	}

	vbo: u32 = ---

	OpenGL.GenBuffers(1, &vbo)
	OpenGL.BindBuffer(OpenGL.ARRAY_BUFFER, vbo)
	defer OpenGL.BindBuffer(OpenGL.ARRAY_BUFFER, 0)

	OpenGL.BufferData(OpenGL.ARRAY_BUFFER, size_of(verts), &verts, OpenGL.STATIC_DRAW)
	OpenGL.VertexAttribPointer(0, 2, OpenGL.FLOAT, false, 0, 0)
	OpenGL.EnableVertexAttribArray(0)

	return vao
}

render :: proc(point_vao: u32, point_shader: u32) {
	OpenGL.Clear(OpenGL.COLOR_BUFFER_BIT)

	OpenGL.UseProgram(point_shader)
	OpenGL.BindVertexArray(point_vao)
	defer OpenGL.BindVertexArray(0)

	// TODO(garrett): Dynamically determine counts
	OpenGL.DrawArrays(OpenGL.POINTS, 0, 4)
}

main :: proc() {
	init_glfw()
	defer glfw.Terminate()

	window := create_glfw_window()
	defer glfw.DestroyWindow(window)

	init_opengl()
	point_vao := prepare_point_buffer_vao()
	point_shader := create_shader_program(
		"shaders/vertex.glsl",
		"shaders/fragment.glsl"
	)

	defer OpenGL.DeleteProgram(point_shader)

	for {
		if (glfw.WindowShouldClose(window)) {
			break
		}

		// TODO(garrett): Add mouse data to affect rendering, possibly through
		// a uniform so that we can highlight selections
		render(point_vao, point_shader)

		glfw.SwapBuffers(window)
		glfw.PollEvents()
	}
}
