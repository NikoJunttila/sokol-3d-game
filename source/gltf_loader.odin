package game

import "core:strings"
import "core:log"
import "core:math/linalg"
import "vendor:cgltf"

Skinned_Vertex :: struct {
	pos:     [3]f32,
	norm:    [3]f32,
	uv:      [2]f32,
	joints:  [4]f32,
	weights: [4]f32,
}

Animated_Model :: struct {
	vertices: [dynamic]Skinned_Vertex,
	indices:  [dynamic]u16,
	
	// Skeleton
	nodes:       [dynamic]Node,
	skins:       [dynamic]Skin,
	animations:  [dynamic]Animation,
}

Node :: struct {
	parent:      int, // -1 if root
	children:    [dynamic]int,
	
	translation: [3]f32,
	rotation:    [4]f32, // Quaternion
	scale:       [3]f32,
	
	local_matrix: matrix[4,4]f32,
	global_matrix: matrix[4,4]f32,
}

Skin :: struct {
	joints:              [dynamic]int, // Indices into nodes array
	inverse_bind_matrices: [dynamic]matrix[4,4]f32,
}

Animation :: struct {
	name:     string,
	channels: [dynamic]Channel,
	duration: f32,
}

Channel :: struct {
	node_index: int,
	path:       cgltf.animation_path_type,
	sampler:    Sampler,
}

Sampler :: struct {
	input:         [dynamic]f32, // Times
	output:        [dynamic]f32, // Values (vec3 or vec4)
	interpolation: cgltf.interpolation_type,
}

load_gltf :: proc(filename: string) -> (Animated_Model, bool) {
	options := cgltf.options{}
	c_filename := strings.clone_to_cstring(filename, context.temp_allocator)
	data, result := cgltf.parse_file(options, c_filename)
	if result != .success {
		log.errorf("Failed to parse GLTF: %v", result)
		return {}, false
	}
	defer cgltf.free(data)

	if result = cgltf.load_buffers(options, data, c_filename); result != .success {
		log.errorf("Failed to load buffers: %v", result)
		return {}, false
	}

	model: Animated_Model
	
	// --- Load Nodes ---
	// Map cgltf_node pointer to index
	node_map := make(map[^cgltf.node]int)
	defer delete(node_map)
	
	for i := 0; i < len(data.nodes); i += 1 {
		node_map[&data.nodes[i]] = i
		
		n: Node
		n.parent = -1
		n.translation = data.nodes[i].translation
		n.rotation = data.nodes[i].rotation
		n.scale = data.nodes[i].scale
		n.local_matrix = linalg.MATRIX4F32_IDENTITY
		n.global_matrix = linalg.MATRIX4F32_IDENTITY
		
		append(&model.nodes, n)
	}
	
	// Set parents and children
	for i := 0; i < len(data.nodes); i += 1 {
		src := &data.nodes[i]
		for j := 0; j < len(src.children); j += 1 {
			child_idx := node_map[src.children[j]]
			model.nodes[child_idx].parent = i
			append(&model.nodes[i].children, child_idx)
		}
	}

	// --- Load Mesh ---
	// Assuming single mesh for simplicity, or merging all meshes
	for i := 0; i < len(data.meshes); i += 1 {
		mesh := &data.meshes[i]
		for j := 0; j < len(mesh.primitives); j += 1 {
			prim := &mesh.primitives[j]
			
			// Indices
			idx_acc := prim.indices
			if idx_acc != nil {
				// Read indices
				count := int(idx_acc.count)
				for k := 0; k < count; k += 1 {
					idx := cgltf.accessor_read_index(idx_acc, uint(k))
					append(&model.indices, u16(idx)) // Assuming u16 fits
				}
			}
			
			// Attributes
			pos_acc: ^cgltf.accessor
			norm_acc: ^cgltf.accessor
			uv_acc: ^cgltf.accessor
			joints_acc: ^cgltf.accessor
			weights_acc: ^cgltf.accessor
			
			for k := 0; k < len(prim.attributes); k += 1 {
				attr := &prim.attributes[k]
				switch attr.type {
				case .position: pos_acc = attr.data
				case .normal:   norm_acc = attr.data
				case .texcoord: uv_acc = attr.data
				case .joints:   joints_acc = attr.data
				case .weights:  weights_acc = attr.data
				case .color, .tangent, .custom, .invalid: // Ignore
				}
			}
			
			vertex_count := int(pos_acc.count)
			
			for k := 0; k < vertex_count; k += 1 {
				v: Skinned_Vertex
				
				if pos_acc != nil { _ = cgltf.accessor_read_float(pos_acc, uint(k), &v.pos[0], 3) }
				if norm_acc != nil { _ = cgltf.accessor_read_float(norm_acc, uint(k), &v.norm[0], 3) }
				if uv_acc != nil { _ = cgltf.accessor_read_float(uv_acc, uint(k), &v.uv[0], 2) }
				
				if joints_acc != nil {
					joints_f: [4]f32
					_ = cgltf.accessor_read_float(joints_acc, uint(k), &joints_f[0], 4)
					v.joints[0] = joints_f[0]
					v.joints[1] = joints_f[1]
					v.joints[2] = joints_f[2]
					v.joints[3] = joints_f[3]
				}
				
				if weights_acc != nil { _ = cgltf.accessor_read_float(weights_acc, uint(k), &v.weights[0], 4) }
				
				append(&model.vertices, v)
			}
		}
	}
	
	// --- Load Skins ---
	for i := 0; i < len(data.skins); i += 1 {
		src := &data.skins[i]
		s: Skin
		
		for j := 0; j < len(src.joints); j += 1 {
			append(&s.joints, node_map[src.joints[j]])
		}
		
		if src.inverse_bind_matrices != nil {
			count := int(src.inverse_bind_matrices.count)
			for j := 0; j < count; j += 1 {
				m: matrix[4,4]f32
				_ = cgltf.accessor_read_float(src.inverse_bind_matrices, uint(j), &m[0,0], 16)
				append(&s.inverse_bind_matrices, m)
			}
		}
		
		append(&model.skins, s)
	}
	
	// --- Load Animations ---
	for i := 0; i < len(data.animations); i += 1 {
		src := &data.animations[i]
		anim: Animation
		if src.name != nil { anim.name = string(src.name) }
		
		for j := 0; j < len(src.channels); j += 1 {
			ch_src := &src.channels[j]
			ch: Channel
			ch.node_index = node_map[ch_src.target_node]
			ch.path = ch_src.target_path
			
			samp_src := ch_src.sampler
			ch.sampler.interpolation = samp_src.interpolation
			
			// Input (Times)
			count := int(samp_src.input.count)
			for k := 0; k < count; k += 1 {
				t: f32
				_ = cgltf.accessor_read_float(samp_src.input, uint(k), &t, 1)
				append(&ch.sampler.input, t)
				if t > anim.duration { anim.duration = t }
			}
			
			// Output (Values)
			// Stride depends on path (translation/scale=3, rotation=4)
			stride := 3
			if ch.path == .rotation { stride = 4 }
			
			for k := 0; k < count; k += 1 {
				val: [4]f32
				_ = cgltf.accessor_read_float(samp_src.output, uint(k), &val[0], uint(stride))
				append(&ch.sampler.output, val[0])
				append(&ch.sampler.output, val[1])
				append(&ch.sampler.output, val[2])
				if stride == 4 { append(&ch.sampler.output, val[3]) }
			}
			
			append(&anim.channels, ch)
		}
		
		append(&model.animations, anim)
	}

	return model, true
}
