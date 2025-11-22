/*
This file is the starting point of your game.

Some importants procedures:
- game_init: Initializes sokol_gfx and sets up the game state.
- game_frame: Called one per frame, do your game logic and rendering in here.
- game_cleanup: Called on shutdown of game, cleanup memory etc.

The hot reload compiles the contents of this folder into a game DLL. A host
application loads that DLL and calls the procedures of the DLL. 

Special procedures that help facilitate the hot reload:
- game_memory: Run just before a hot reload. The hot reload host application can
	that way keep a pointer to the game's memory and feed it to the new game DLL
	after the hot reload is complete.
- game_hot_reloaded: Sets the `g` global variable in the new game DLL. The value
	comes from the value the host application got from game_memory before the
	hot reload.

When release or web builds are made, then this whole package is just
treated as a normal Odin package. No DLL is created.

The hot applications use sokol_app to open the window. They use the settings
returned by the `game_app_default_desc` procedure.
*/

package game

import "core:math/linalg"
import "core:image/png"
import "core:log"
import "core:slice"
import sapp "sokol/app"
import sg "sokol/gfx"
import sglue "sokol/glue"
import slog "sokol/log"

Game_Memory :: struct {
	pip: sg.Pipeline,
	bind: sg.Bindings,
	rx, ry: f32,
	
	// Camera state
	camera_pos: Vec3,
	camera_front: Vec3,
	camera_up: Vec3,
	yaw, pitch: f32,
	
	// Input state
	keys: map[sapp.Keycode]bool,
	mouse_locked: bool,
	last_mouse_x, last_mouse_y: f32,
	first_mouse: bool,

	// Player model
	player_bind: sg.Bindings,
	player_indices_count: int,
	
	// Player state
	player_pos: Vec3,
	player_vel: Vec3,
	player_rot: f32,
	on_ground: bool,
}

Mat4 :: matrix[4,4]f32
Vec3 :: [3]f32
g: ^Game_Memory

Vertex :: struct {
	x, y, z: f32,
	color: u32,
	u, v: u16,
}

@export
game_app_default_desc :: proc() -> sapp.Desc {
	return {
		width = 1280,
		height = 720,
		sample_count = 4,
		window_title = "Odin + Sokol hot reload template",
		icon = { sokol_default = true },
		logger = { func = slog.func },
		html5_update_document_title = true,
	}
}

@export
game_init :: proc() {
	g = new(Game_Memory)

	game_hot_reloaded(g)

	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
	})

	// Initialize camera
	g.camera_pos = {0.0, 0.0, 6.0}
	g.camera_front = {0.0, 0.0, -1.0}
	g.camera_up = {0.0, 1.0, 0.0}
	g.yaw = -90.0
	g.pitch = -20.0 // Look down slightly
	g.first_mouse = true
	g.mouse_locked = false
	
	// Initialize player
	g.player_pos = {0.0, -2.0, 0.0}
	g.player_vel = {0.0, 0.0, 0.0}
	g.player_rot = 0.0
	g.on_ground = true

	// The remainder of this proc just sets up a sample cube and loads the
	// texture to put on the cube's sides.
	//
	// The cube is from https://github.com/floooh/sokol-odin/blob/main/examples/cube/main.odin

	/*
		Cube vertex buffer with packed vertex formats for color and texture coords.
		Note that a vertex format which must be portable across all
		backends must only use the normalized integer formats
		(BYTE4N, UBYTE4N, SHORT2N, SHORT4N), which can be converted
		to floating point formats in the vertex shader inputs.
	*/

	vertices := [?]Vertex {
		// pos               color       uvs
		{ -1.0, -1.0, -1.0,  0xFF0000FF,     0,     0 },
		{  1.0, -1.0, -1.0,  0xFF0000FF, 32767,     0 },
		{  1.0,  1.0, -1.0,  0xFF0000FF, 32767, 32767 },
		{ -1.0,  1.0, -1.0,  0xFF0000FF,     0, 32767 },

		{ -1.0, -1.0,  1.0,  0xFF00FF00,     0,     0 },
		{  1.0, -1.0,  1.0,  0xFF00FF00, 32767,     0 },
		{  1.0,  1.0,  1.0,  0xFF00FF00, 32767, 32767 },
		{ -1.0,  1.0,  1.0,  0xFF00FF00,     0, 32767 },

		{ -1.0, -1.0, -1.0,  0xFFFF0000,     0,     0 },
		{ -1.0,  1.0, -1.0,  0xFFFF0000, 32767,     0 },
		{ -1.0,  1.0,  1.0,  0xFFFF0000, 32767, 32767 },
		{ -1.0, -1.0,  1.0,  0xFFFF0000,     0, 32767 },

		{  1.0, -1.0, -1.0,  0xFFFF007F,     0,     0 },
		{  1.0,  1.0, -1.0,  0xFFFF007F, 32767,     0 },
		{  1.0,  1.0,  1.0,  0xFFFF007F, 32767, 32767 },
		{  1.0, -1.0,  1.0,  0xFFFF007F,     0, 32767 },

		{ -1.0, -1.0, -1.0,  0xFFFF7F00,     0,     0 },
		{ -1.0, -1.0,  1.0,  0xFFFF7F00, 32767,     0 },
		{  1.0, -1.0,  1.0,  0xFFFF7F00, 32767, 32767 },
		{  1.0, -1.0, -1.0,  0xFFFF7F00,     0, 32767 },

		{ -1.0,  1.0, -1.0,  0xFF007FFF,     0,     0 },
		{ -1.0,  1.0,  1.0,  0xFF007FFF, 32767,     0 },
		{  1.0,  1.0,  1.0,  0xFF007FFF, 32767, 32767 },
		{  1.0,  1.0, -1.0,  0xFF007FFF,     0, 32767 },
	}
	g.bind.vertex_buffers[0] = sg.make_buffer({
		data = { ptr = &vertices, size = size_of(vertices) },
	})

	// create an index buffer for the cube
	indices := [?]u16 {
		0, 1, 2,  0, 2, 3,
		6, 5, 4,  7, 6, 4,
		8, 9, 10,  8, 10, 11,
		14, 13, 12,  15, 14, 12,
		16, 17, 18,  16, 18, 19,
		22, 21, 20,  23, 22, 20,
	}
	g.bind.index_buffer = sg.make_buffer({
		usage = {
			index_buffer = true,
		},
		data = { ptr = &indices, size = size_of(indices) },
	})

	if img_data, img_data_ok := read_entire_file("assets/round_cat.png", context.temp_allocator); img_data_ok {
		if img, img_err := png.load_from_bytes(img_data, allocator = context.temp_allocator); img_err == nil {
			sg_img := sg.make_image({
				width = i32(img.width),
				height = i32(img.height),
				data = {
					mip_levels = {
						0 = {
							ptr = raw_data(img.pixels.buf),
							size = uint(slice.size(img.pixels.buf[:])),
						},
					},
				},
			})

			g.bind.views[VIEW_tex] = sg.make_view({
				texture = sg.Texture_View_Desc({image = sg_img}),
			})
		} else {
			log.error(img_err)
		}
	} else {
		log.error("Failed loading texture")
	}

	// a sampler with default options to sample the above image as texture
	g.bind.samplers[SMP_smp] = sg.make_sampler({})

	// Load player model
	if mesh, ok := load_obj("assets/cat.obj"); ok {
		g.player_indices_count = len(mesh.indices)
		
		g.player_bind.vertex_buffers[0] = sg.make_buffer({
			data = { ptr = raw_data(mesh.vertices), size = uint(len(mesh.vertices) * size_of(Vertex)) },
		})
		
		g.player_bind.index_buffer = sg.make_buffer({
			usage = { index_buffer = true },
			data = { ptr = raw_data(mesh.indices), size = uint(len(mesh.indices) * size_of(u16)) },
		})

		// Load player texture (try png first, fallback to existing if needed)
		// Assuming user converted it or we use round_cat.png as placeholder if missing
		// But let's try to load Cat_diffuse.png if it exists, otherwise round_cat.png
		
		tex_path := "assets/Cat_diffuse.png"
		// Simple check if file exists by trying to read it (inefficient but simple here)
		// Actually read_entire_file returns bool
		
		if img_data, img_data_ok := read_entire_file(tex_path, context.temp_allocator); img_data_ok {
			if img, img_err := png.load_from_bytes(img_data, allocator = context.temp_allocator); img_err == nil {
				sg_img := sg.make_image({
					width = i32(img.width),
					height = i32(img.height),
					data = { mip_levels = { 0 = { ptr = raw_data(img.pixels.buf), size = uint(slice.size(img.pixels.buf[:])) } } },
				})
				g.player_bind.views[VIEW_tex] = sg.make_view({ texture = sg.Texture_View_Desc({image = sg_img}) })
			} else {
				log.error(img_err)
			}
		} else {
			// Fallback to round_cat.png (already loaded in g.bind, but we need it in player_bind)
			// We can reuse the image handle if we stored it, but we didn't.
			// So let's just load round_cat.png again for simplicity or assume user provided the file.
			// For now, let's just use the same texture as the cube if the specific one fails?
			// Actually, let's just copy the view from g.bind if we want to reuse
			g.player_bind.views[VIEW_tex] = g.bind.views[VIEW_tex]
		}
		
		g.player_bind.samplers[SMP_smp] = sg.make_sampler({})
	} else {
		log.error("Failed to load assets/cat.obj")
	}

	// shader and pipeline object
	g.pip = sg.make_pipeline({
		shader = sg.make_shader(texcube_shader_desc(sg.query_backend())),
		layout = {
			attrs = {
				ATTR_texcube_pos = { format = .FLOAT3 },
				ATTR_texcube_color0 = { format = .UBYTE4N },
				ATTR_texcube_texcoord0 = { format = .SHORT2N },
			},
		},
		index_type = .UINT16,
		cull_mode = .BACK,
		depth = {
			compare = .LESS_EQUAL,
			write_enabled = true,
		},
	})
}

@export
game_frame :: proc() {
	dt := f32(sapp.frame_duration())
	g.rx += 60 * dt
	g.ry += 120 * dt

	// --- Player Physics & Movement ---
	
	// Gravity
	GRAVITY :: 20.0
	g.player_vel.y -= GRAVITY * dt

	// Movement Input
	move_speed: f32 = 10.0
	move_dir: Vec3 = {0, 0, 0}
	
	// Calculate forward/right vectors relative to camera (ignoring Y)
	cam_forward := g.camera_front
	cam_forward.y = 0
	cam_forward = linalg.normalize(cam_forward)
	
	cam_right := linalg.normalize(linalg.cross(cam_forward, Vec3{0, 1, 0}))

	if g.keys[.W] { move_dir += cam_forward }
	if g.keys[.S] { move_dir -= cam_forward }
	if g.keys[.A] { move_dir -= cam_right }
	if g.keys[.D] { move_dir += cam_right }

	if linalg.length(move_dir) > 0.1 {
		move_dir = linalg.normalize(move_dir)
		g.player_pos.x += move_dir.x * move_speed * dt
		g.player_pos.z += move_dir.z * move_speed * dt
		
		// Rotate player to face movement direction
		// atan2 returns angle in radians from X axis, we want rotation around Y
		// We need to map (x, z) to angle.
		// standard atan2(y, x) -> here atan2(x, z) or similar
		target_rot := linalg.to_degrees(linalg.atan2(move_dir.x, move_dir.z))
		
		// Smooth rotation could be added here, but instant snap for now
		g.player_rot = target_rot
	}
	
	// Apply vertical velocity
	g.player_pos.y += g.player_vel.y * dt

	// --- Collision Detection ---
	
	// Floor constraint (floor is at y=-2.0)
	// Assuming player origin is at feet
	if g.player_pos.y < -2.0 {
		g.player_pos.y = -2.0
		g.player_vel.y = 0
		g.on_ground = true
	} else {
		g.on_ground = false
	}

	// Wall constraints (walls are at +/- 20.0, keep player within +/- 18.0)
	if g.player_pos.x > 18.0 { g.player_pos.x = 18.0 }
	if g.player_pos.x < -18.0 { g.player_pos.x = -18.0 }
	if g.player_pos.z > 18.0 { g.player_pos.z = 18.0 }
	if g.player_pos.z < -18.0 { g.player_pos.z = -18.0 }

	// --- Camera Follow ---
	
	// Camera orbits around player
	camera_dist: f32 = 8.0
	camera_height: f32 = 3.0 // Height offset from player
	
	// Target point is player position + height
	target := g.player_pos
	target.y += 1.5 // Look at head/center
	
	// Camera position based on orbit angles (yaw/pitch)
	// We already update camera_front based on mouse input in game_event
	// So we just place camera backwards from target along that vector
	
	g.camera_pos = target - (g.camera_front * camera_dist)
	
	// Calculate View-Projection Matrix
	proj := linalg.matrix4_perspective(60.0 * linalg.RAD_PER_DEG, sapp.widthf() / sapp.heightf(), 0.01, 100.0)
	view := linalg.matrix4_look_at_f32(g.camera_pos, target, g.camera_up)
	view_proj := proj * view

	pass_action := sg.Pass_Action {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 0.41, 0.68, 0.83, 1 } },
		},
	}

	sg.begin_pass({ action = pass_action, swapchain = sglue.swapchain() })
	sg.apply_pipeline(g.pip)
	sg.apply_bindings(g.bind)

	// Draw Rotating Cube (keep it as a landmark)
	rxm := linalg.matrix4_rotate_f32(g.rx * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
	rym := linalg.matrix4_rotate_f32(g.ry * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
	model_cube := rxm * rym
	
	vs_params_cube := Vs_Params {
		mvp = view_proj * model_cube,
	}
	sg.apply_uniforms(UB_vs_params, { ptr = &vs_params_cube, size = size_of(vs_params_cube) })
	sg.draw(0, 36, 1)

	// Draw Ground
	model_ground := linalg.matrix4_translate_f32({0.0, -2.0, 0.0}) * linalg.matrix4_scale_f32({20.0, 0.1, 20.0})
	
	vs_params_ground := Vs_Params {
		mvp = view_proj * model_ground,
	}
	sg.apply_uniforms(UB_vs_params, { ptr = &vs_params_ground, size = size_of(vs_params_ground) })
	sg.draw(0, 36, 1)

	// Draw Walls
	// North
	model_wall_n := linalg.matrix4_translate_f32({0.0, 0.0, 20.0}) * linalg.matrix4_scale_f32({20.0, 2.0, 1.0})
	vs_params_wall_n := Vs_Params { mvp = view_proj * model_wall_n }
	sg.apply_uniforms(UB_vs_params, { ptr = &vs_params_wall_n, size = size_of(vs_params_wall_n) })
	sg.draw(0, 36, 1)

	// South
	model_wall_s := linalg.matrix4_translate_f32({0.0, 0.0, -20.0}) * linalg.matrix4_scale_f32({20.0, 2.0, 1.0})
	vs_params_wall_s := Vs_Params { mvp = view_proj * model_wall_s }
	sg.apply_uniforms(UB_vs_params, { ptr = &vs_params_wall_s, size = size_of(vs_params_wall_s) })
	sg.draw(0, 36, 1)

	// East
	model_wall_e := linalg.matrix4_translate_f32({20.0, 0.0, 0.0}) * linalg.matrix4_scale_f32({1.0, 2.0, 20.0})
	vs_params_wall_e := Vs_Params { mvp = view_proj * model_wall_e }
	sg.apply_uniforms(UB_vs_params, { ptr = &vs_params_wall_e, size = size_of(vs_params_wall_e) })
	sg.draw(0, 36, 1)

	// West
	model_wall_w := linalg.matrix4_translate_f32({-20.0, 0.0, 0.0}) * linalg.matrix4_scale_f32({1.0, 2.0, 20.0})
	vs_params_wall_w := Vs_Params { mvp = view_proj * model_wall_w }
	sg.apply_uniforms(UB_vs_params, { ptr = &vs_params_wall_w, size = size_of(vs_params_wall_w) })
	sg.draw(0, 36, 1)

	sg.apply_uniforms(UB_vs_params, { ptr = &vs_params_wall_w, size = size_of(vs_params_wall_w) })
	sg.draw(0, 36, 1)

	// Draw Player Model
	if g.player_indices_count > 0 {
		sg.apply_bindings(g.player_bind)
		
		// Render player at player_pos with player_rot
		model_player := linalg.matrix4_translate_f32(g.player_pos) * 
						linalg.matrix4_rotate_f32(g.player_rot * linalg.RAD_PER_DEG, {0, 1, 0}) * 
						linalg.matrix4_scale_f32({0.1, 0.1, 0.1})
		
		vs_params_player := Vs_Params { mvp = view_proj * model_player }
		sg.apply_uniforms(UB_vs_params, { ptr = &vs_params_player, size = size_of(vs_params_player) })
		sg.draw(0, g.player_indices_count, 1)
	}

	sg.end_pass()
	sg.commit()

	free_all(context.temp_allocator)
}



force_reset: bool

@export
game_event :: proc(e: ^sapp.Event) {
	#partial switch e.type {
	case .KEY_DOWN:
		if e.key_code == .F6 {
			force_reset = true
		}
		g.keys[e.key_code] = true
		
		if e.key_code == .TAB {
			g.mouse_locked = !g.mouse_locked
			sapp.lock_mouse(g.mouse_locked)
			g.first_mouse = true
		}
		
		if e.key_code == .SPACE && g.on_ground {
			g.player_vel.y = 10.0 // Jump force
		}

	case .KEY_UP:
		g.keys[e.key_code] = false

	case .MOUSE_MOVE:
		if g.mouse_locked {
			if g.first_mouse {
				g.last_mouse_x = e.mouse_x
				g.last_mouse_y = e.mouse_y
				g.first_mouse = false
			}

			xoffset := e.mouse_x - g.last_mouse_x
			yoffset := g.last_mouse_y - e.mouse_y // reversed since y-coordinates go from bottom to top
			g.last_mouse_x = e.mouse_x
			g.last_mouse_y = e.mouse_y

			sensitivity: f32 = 0.1
			xoffset *= sensitivity
			yoffset *= sensitivity

			g.yaw += xoffset
			g.pitch += yoffset

			// make sure that when pitch is out of bounds, screen doesn't get flipped
			if g.pitch > 89.0 {
				g.pitch = 89.0
			}
			if g.pitch < -89.0 {
				g.pitch = -89.0
			}

			front: Vec3
			front.x = linalg.cos(linalg.to_radians(g.yaw)) * linalg.cos(linalg.to_radians(g.pitch))
			front.y = linalg.sin(linalg.to_radians(g.pitch))
			front.z = linalg.sin(linalg.to_radians(g.yaw)) * linalg.cos(linalg.to_radians(g.pitch))
			g.camera_front = linalg.normalize(front)
		}
	}
}

@export
game_cleanup :: proc() {
	sg.shutdown()
	free(g)
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside
	// `g`. Then that state carries over between hot reloads.
}

@(export)
game_force_restart :: proc() -> bool {
	return force_reset
}

