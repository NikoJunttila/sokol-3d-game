package game

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:log"

Mesh :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]u16,
}

load_obj :: proc(filename: string) -> (Mesh, bool) {
	data, ok := read_entire_file(filename)
	if !ok {
		log.errorf("Failed to read file: %s", filename)
		return {}, false
	}
	defer delete(data)

	content := string(data)
	
	positions: [dynamic]Vec3
	texcoords: [dynamic][2]f32
	normals:   [dynamic]Vec3
	
	mesh: Mesh
	
	// Map to keep track of unique vertices to reuse indices
	// Key is "v/vt/vn" string, Value is index
	unique_vertices := make(map[string]u16)
	defer delete(unique_vertices)

	it := content
	for line in strings.split_iterator(&it, "\n") {
		line := strings.trim_space(line)
		if len(line) == 0 || line[0] == '#' {
			continue
		}

		parts := strings.fields(line)
		defer delete(parts)
		if len(parts) == 0 {
			continue
		}

		switch parts[0] {
		case "v":
			if len(parts) >= 4 {
				x, _ := strconv.parse_f32(parts[1])
				y, _ := strconv.parse_f32(parts[2])
				z, _ := strconv.parse_f32(parts[3])
				append(&positions, Vec3{x, y, z})
			}
		case "vt":
			if len(parts) >= 3 {
				u, _ := strconv.parse_f32(parts[1])
				v, _ := strconv.parse_f32(parts[2])
				append(&texcoords, [2]f32{u, v})
			}
		case "vn":
			if len(parts) >= 4 {
				x, _ := strconv.parse_f32(parts[1])
				y, _ := strconv.parse_f32(parts[2])
				z, _ := strconv.parse_f32(parts[3])
				append(&normals, Vec3{x, y, z})
			}
		case "f":
			// Handle faces (triangulate if necessary)
			// f v1/vt1/vn1 v2/vt2/vn2 v3/vt3/vn3 ...
			face_indices: [dynamic]u16
			defer delete(face_indices)

			for i := 1; i < len(parts); i += 1 {
				key := parts[i]
				if idx, ok := unique_vertices[key]; ok {
					append(&face_indices, idx)
				} else {
					// Parse index triplet
					v_idx, vt_idx, vn_idx: int
					
					components := strings.split(key, "/")
					defer delete(components)
					
					if len(components) > 0 { v_idx, _ = strconv.parse_int(components[0]) }
					if len(components) > 1 { vt_idx, _ = strconv.parse_int(components[1]) }
					if len(components) > 2 { vn_idx, _ = strconv.parse_int(components[2]) }

					// Create new vertex
					vertex: Vertex
					
					// OBJ indices are 1-based
					if v_idx > 0 && v_idx <= len(positions) {
						vertex.x = positions[v_idx-1].x
						vertex.y = positions[v_idx-1].y
						vertex.z = positions[v_idx-1].z
					}
					
					if vt_idx > 0 && vt_idx <= len(texcoords) {
						// Convert float UVs to u16 normalized
						vertex.u = u16(texcoords[vt_idx-1].x * 32767)
						vertex.v = u16((1.0 - texcoords[vt_idx-1].y) * 32767) // Flip V
					}
					
					// We are ignoring normals for now as Vertex struct doesn't have them
					// But we could add them later if needed for lighting

					vertex.color = 0xFFFFFFFF // White default

					new_idx := u16(len(mesh.vertices))
					append(&mesh.vertices, vertex)
					unique_vertices[key] = new_idx
					append(&face_indices, new_idx)
				}
			}

			// Triangulate fan
			if len(face_indices) >= 3 {
				for i := 1; i < len(face_indices)-1; i += 1 {
					append(&mesh.indices, face_indices[0])
					append(&mesh.indices, face_indices[i])
					append(&mesh.indices, face_indices[i+1])
				}
			}
		}
	}

	return mesh, true
}
