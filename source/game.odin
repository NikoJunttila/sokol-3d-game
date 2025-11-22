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
import sdt "sokol/debugtext"

Game_Memory :: struct {
	pip: sg.Pipeline,
	pip_skinned: sg.Pipeline,
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
	player_scale: f32,
	on_ground: bool,
	
	// Map system
	current_map: Map,
	edit_mode: bool,
	selected_type: Map_Object_Type,
	placement_rot: f32,
	
	// Animation
	animated_model: Animated_Model,
	anim_time: f32,
	current_anim: int,
	joint_matrices: [64]matrix[4,4]f32,
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
	g.player_scale = 0.5
	g.on_ground = true
	
	// Initialize map
	if m, ok := load_map("assets/level1.map"); ok {
		g.current_map = m
	} else {
		// Create default map if load fails
		append(&g.current_map.objects, Map_Object{type = .Floor, pos = {0, -2, 0}, scale = {20, 0.1, 20}})
		// Walls
		append(&g.current_map.objects, Map_Object{type = .Wall, pos = {0, 0, 20}, scale = {20, 2, 1}})
		append(&g.current_map.objects, Map_Object{type = .Wall, pos = {0, 0, -20}, scale = {20, 2, 1}})
		append(&g.current_map.objects, Map_Object{type = .Wall, pos = {20, 0, 0}, scale = {1, 2, 20}})
		append(&g.current_map.objects, Map_Object{type = .Wall, pos = {-20, 0, 0}, scale = {1, 2, 20}})
	}
	
	g.selected_type = .Wall

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
	
	// Load animated model
	if model, ok := load_gltf("assets/cat_model.glb"); ok {
		g.animated_model = model
		g.current_anim = 0 // Default animation
		
		// Create buffers for animated model
		// We need to repack vertices to match shader layout if needed, but our Skinned_Vertex matches
		// Layout: pos(0), color(1), uv(2), joints(3), weights(4)
		// Wait, Skinned_Vertex has pos, norm, uv, joints, weights.
		// Shader expects: pos(0), color0(1), texcoord0(2), joints(3), weights(4)
		// We don't have color in Skinned_Vertex, but we have norm.
		// We should probably update shader to use norm or just ignore color.
		// Or we can map norm to color for debugging?
		// Let's update pipeline layout below.
		
		g.player_bind.vertex_buffers[0] = sg.make_buffer({
			data = { ptr = raw_data(model.vertices), size = uint(len(model.vertices) * size_of(Skinned_Vertex)) },
		})
		
		g.player_bind.index_buffer = sg.make_buffer({
			usage = { index_buffer = true },
			data = { ptr = raw_data(model.indices), size = uint(len(model.indices) * size_of(u16)) },
		})
		
		// Reuse texture view
		g.player_bind.views[VIEW_tex] = g.bind.views[VIEW_tex] // Or load specific texture
		g.player_bind.samplers[SMP_smp] = sg.make_sampler({})
		
	} else {
		log.error("Failed to load assets/cat_model.glb")
	}

	// shader and pipeline object
	
	// Original Shader for Static Meshes (Map, Cube)
	// Use the generated shader description which handles multiple backends
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

	// Skinning Shader for Animated Player
	g.pip_skinned = sg.make_pipeline({
		shader = sg.make_shader(skinned_shader_desc(sg.query_backend())),
		layout = {
			attrs = {
				ATTR_skinned_pos = { format = .FLOAT3 },
				ATTR_skinned_color0 = { format = .FLOAT3 }, // color/norm
				ATTR_skinned_texcoord0 = { format = .FLOAT2 },
				ATTR_skinned_joints = { format = .FLOAT4 },
				ATTR_skinned_weights = { format = .FLOAT4 },
			},
		},
		index_type = .UINT16,
		cull_mode = .BACK,
		depth = {
			compare = .LESS_EQUAL,
			write_enabled = true,
		},
	})

	// Initialize sokol_debugtext
	sdt.setup({
		fonts = {
			0 = sdt.font_kc853(),
			1 = sdt.font_kc854(),
			2 = sdt.font_z1013(),
			3 = sdt.font_cpc(),
			4 = sdt.font_c64(),
			5 = sdt.font_oric(),
		},
	})
}

@export
game_frame :: proc() {
	dt := f32(sapp.frame_duration())
	g.rx += 60 * dt
	g.ry += 120 * dt
	
	// --- Animation Update ---
	if len(g.animated_model.animations) > 0 {
		anim := &g.animated_model.animations[g.current_anim]
		g.anim_time += dt
		if g.anim_time > anim.duration {
			g.anim_time = 0 // Loop
		}
		
		// Sample channels
		for ch in anim.channels {
			// Simple linear search for keyframes (optimize later)
			// Input times
			times := ch.sampler.input
			values := ch.sampler.output
			
			// Find frame
			frame := 0
			for i := 0; i < len(times)-1; i += 1 {
				if g.anim_time >= times[i] && g.anim_time < times[i+1] {
					frame = i
					break
				}
			}
			
			next_frame := frame + 1
			if next_frame >= len(times) { next_frame = frame }
			
			t0 := times[frame]
			t1 := times[next_frame]
			factor := (g.anim_time - t0) / (t1 - t0)
			if t1 == t0 { factor = 0 }
			
			node := &g.animated_model.nodes[ch.node_index]
			
			if ch.path == .translation {
				idx0 := frame * 3
				idx1 := next_frame * 3
				v0 := Vec3{values[idx0], values[idx0+1], values[idx0+2]}
				v1 := Vec3{values[idx1], values[idx1+1], values[idx1+2]}
				node.translation = linalg.lerp(v0, v1, factor)
			} else if ch.path == .rotation {
				idx0 := frame * 4
				idx1 := next_frame * 4
				q0 := quaternion(w=values[idx0+3], x=values[idx0], y=values[idx0+1], z=values[idx0+2])
				q1 := quaternion(w=values[idx1+3], x=values[idx1], y=values[idx1+1], z=values[idx1+2])
				res_q := linalg.quaternion_nlerp(q0, q1, factor)
				node.rotation = {res_q.x, res_q.y, res_q.z, res_q.w}
			} else if ch.path == .scale {
				idx0 := frame * 3
				idx1 := next_frame * 3
				v0 := Vec3{values[idx0], values[idx0+1], values[idx0+2]}
				v1 := Vec3{values[idx1], values[idx1+1], values[idx1+2]}
				node.scale = linalg.lerp(v0, v1, factor)
			}
		}
		
		// Update global matrices
		// Assuming root nodes are those with parent == -1
		for i := 0; i < len(g.animated_model.nodes); i += 1 {
			if g.animated_model.nodes[i].parent == -1 {
				update_node_hierarchy(&g.animated_model, i, linalg.MATRIX4F32_IDENTITY)
			}
		}
		
		// Compute joint matrices for skinning
		if len(g.animated_model.skins) > 0 {
			skin := &g.animated_model.skins[0] // Assume single skin
			for i := 0; i < len(skin.joints) && i < 64; i += 1 {
				joint_node_idx := skin.joints[i]
				node := &g.animated_model.nodes[joint_node_idx]
				inv_bind := skin.inverse_bind_matrices[i]
				g.joint_matrices[i] = node.global_matrix * inv_bind
			}
		}
	}

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
	
	// Simple AABB collision against map objects
	// We check if player is inside any wall object
	// Floor collision is still hardcoded to -2.0 for base floor, but we should check map floors too
	
	// Reset on_ground
	g.on_ground = false
	
	// Base floor check (keep as fallback)
	if g.player_pos.y < -2.0 {
		g.player_pos.y = -2.0
		g.player_vel.y = 0
		g.on_ground = true
	}
	
	// Check against map objects
	player_radius: f32 = 0.5
	player_height: f32 = 1.0
	
	for obj in g.current_map.objects {
		// Simple AABB check (ignoring rotation for collision simplicity)
		// Calculate bounds
		// Actually base cube vertices are -1 to 1, so size is 2.
		// So scale of 1 means size 2.
		// Half extents = scale * 1.0
		
		min_bound := obj.pos - obj.scale
		max_bound := obj.pos + obj.scale
		
		// Check if player is intersecting
		if g.player_pos.x + player_radius > min_bound.x && g.player_pos.x - player_radius < max_bound.x &&
		   g.player_pos.z + player_radius > min_bound.z && g.player_pos.z - player_radius < max_bound.z {
			
			// Vertical check
			if g.player_pos.y < max_bound.y && g.player_pos.y + player_height > min_bound.y {
				// Collision detected
				if obj.type == .Floor {
					// Land on top
					if g.player_vel.y <= 0 && g.player_pos.y >= max_bound.y - 0.5 {
						g.player_pos.y = max_bound.y
						g.player_vel.y = 0
						g.on_ground = true
					}
				} else if obj.type == .Wall {
					// Push out horizontally
					// Determine closest face
					dx_pos := abs(g.player_pos.x - max_bound.x)
					dx_neg := abs(g.player_pos.x - min_bound.x)
					dz_pos := abs(g.player_pos.z - max_bound.z)
					dz_neg := abs(g.player_pos.z - min_bound.z)
					
					min_d := min(dx_pos, min(dx_neg, min(dz_pos, dz_neg)))
					
					if min_d == dx_pos { g.player_pos.x = max_bound.x + player_radius }
					else if min_d == dx_neg { g.player_pos.x = min_bound.x - player_radius }
					else if min_d == dz_pos { g.player_pos.z = max_bound.z + player_radius }
					else if min_d == dz_neg { g.player_pos.z = min_bound.z - player_radius }
				}
			}
		}
	}

	// --- Camera Follow ---
	
	// Camera orbits around player
	camera_dist: f32 = 8.0
	
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

	// Draw Map Objects
	for obj in g.current_map.objects {
		model := linalg.matrix4_translate_f32(obj.pos) * 
				 linalg.matrix4_rotate_f32(obj.rot.y * linalg.RAD_PER_DEG, {0, 1, 0}) * 
				 linalg.matrix4_scale_f32(obj.scale)
		
		vs_params := Vs_Params { mvp = view_proj * model }
		sg.apply_uniforms(UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })
		sg.draw(0, 36, 1)
	}
	
	// Editor Preview
	if g.edit_mode {
		// Calculate placement position (snap to grid)
		snap_size: f32 = 2.0
		place_pos := g.player_pos + (g.camera_front * 5.0)
		place_pos.x = f32(int(place_pos.x / snap_size)) * snap_size
		place_pos.y = f32(int(place_pos.y / snap_size)) * snap_size
		place_pos.z = f32(int(place_pos.z / snap_size)) * snap_size
		
		// Default scale based on type
		scale: Vec3 = {1, 1, 1}
		if g.selected_type == .Floor { scale = {2, 0.1, 2} }
		if g.selected_type == .Wall { scale = {2, 2, 1} }
		
		model := linalg.matrix4_translate_f32(place_pos) * 
				 linalg.matrix4_rotate_f32(g.placement_rot * linalg.RAD_PER_DEG, {0, 1, 0}) * 
				 linalg.matrix4_scale_f32(scale)
		
		// Pulsing effect or color change could be added here via uniforms if supported
		// For now just draw it
		vs_params := Vs_Params { mvp = view_proj * model }
		sg.apply_uniforms(UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })
		sg.draw(0, 36, 1)
	}



	// Draw Player Model
	if g.player_indices_count > 0 {
		sg.apply_pipeline(g.pip_skinned)
		sg.apply_bindings(g.player_bind)
		
		// Render player at player_pos with player_rot
		model_player := linalg.matrix4_translate_f32(g.player_pos) * 
						linalg.matrix4_rotate_f32(g.player_rot * linalg.RAD_PER_DEG, {0, 1, 0}) * 
						linalg.matrix4_scale_f32({g.player_scale, g.player_scale, g.player_scale})
		
		vs_params_player := Vs_Params_Skinned { 
			mvp = view_proj * model_player,
			joint_matrices = g.joint_matrices,
		}
		sg.apply_uniforms(UB_vs_params_skinned, { ptr = &vs_params_player, size = size_of(vs_params_player) })
		sg.draw(0, g.player_indices_count, 1) // Use count from animated model if loaded
	}

	// --- UI Text Rendering ---
	// sdt.new_frame() // Not found in binding
	
	// Controls Help (Top Left)
	sdt.font(4) // C64 style
	sdt.color4f(1.0, 1.0, 1.0, 1.0)
	sdt.pos(1, 1)
	sdt.printf("Controls:")
	sdt.pos(1, 2)
	sdt.printf("WASD: Move")
	sdt.pos(1, 3)
	sdt.printf("Space: Jump")
	sdt.pos(1, 4)
	sdt.printf("Mouse: Look")
	sdt.pos(1, 5)
	sdt.printf("Tab: Toggle Mouse Lock")
	sdt.pos(1, 6)
	sdt.printf("F1: Toggle Edit Mode")
	
	// Editor Status (Top Right)
	if g.edit_mode {
		sdt.color4f(1.0, 0.2, 0.2, 1.0) // Red
		sdt.pos(40, 1)
		sdt.printf("EDIT MODE ACTIVE")
		
		sdt.color4f(1.0, 1.0, 1.0, 1.0)
		sdt.pos(40, 2)
		sdt.printf("1: Floor, 2: Wall")
		sdt.pos(40, 3)
		sdt.printf("E: Place, Q: Undo")
		sdt.pos(40, 4)
		sdt.printf("R: Rotate")
		sdt.pos(40, 5)
		sdt.printf("F5: Save, F9: Load")
		
		sdt.pos(40, 7)
		sdt.printf("Selected: ")
		if g.selected_type == .Floor { sdt.printf("Floor") }
		if g.selected_type == .Wall { sdt.printf("Wall") }
	}

	sdt.draw()

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
		
		// Editor Controls
		if e.key_code == .F1 {
			g.edit_mode = !g.edit_mode
			log.info("Edit Mode:", g.edit_mode)
		}
		
		if g.edit_mode {
			if e.key_code == ._1 { g.selected_type = .Floor }
			if e.key_code == ._2 { g.selected_type = .Wall }
			if e.key_code == .R { g.placement_rot += 90.0 }
			
			if e.key_code == .E {
				// Place object
				snap_size: f32 = 2.0
				place_pos := g.player_pos + (g.camera_front * 5.0)
				place_pos.x = f32(int(place_pos.x / snap_size)) * snap_size
				place_pos.y = f32(int(place_pos.y / snap_size)) * snap_size
				place_pos.z = f32(int(place_pos.z / snap_size)) * snap_size
				
				scale: Vec3 = {1, 1, 1}
				if g.selected_type == .Floor { scale = {2, 0.1, 2} }
				if g.selected_type == .Wall { scale = {2, 2, 1} }
				
				append(&g.current_map.objects, Map_Object{
					type = g.selected_type,
					pos = place_pos,
					rot = {0, g.placement_rot, 0},
					scale = scale,
				})
			}
			
			if e.key_code == .Q {
				// Remove last object (simple undo for now)
				if len(g.current_map.objects) > 0 {
					pop(&g.current_map.objects)
				}
			}
			
			if e.key_code == .F5 {
				save_map("assets/level1.map", g.current_map)
				log.info("Map saved")
			}
			
			if e.key_code == .F9 {
				if m, ok := load_map("assets/level1.map"); ok {
					g.current_map = m
					log.info("Map loaded")
				}
			}
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
	sdt.shutdown()
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


update_node_hierarchy :: proc(model: ^Animated_Model, node_idx: int, parent_mat: Mat4) {
	node := &model.nodes[node_idx]
	
	// Recompose local matrix
	t := linalg.matrix4_translate_f32(node.translation)
	q := quaternion(w=node.rotation[3], x=node.rotation[0], y=node.rotation[1], z=node.rotation[2])
	r := linalg.matrix4_from_quaternion_f32(q)
	s := linalg.matrix4_scale_f32(node.scale)
	
	node.local_matrix = t * r * s
	node.global_matrix = parent_mat * node.local_matrix
	
	for child_idx in node.children {
		update_node_hierarchy(model, child_idx, node.global_matrix)
	}
}
