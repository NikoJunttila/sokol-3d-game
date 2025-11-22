package game

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:log"

Map_Object_Type :: enum {
	Floor,
	Wall,
}

Map_Object :: struct {
	type: Map_Object_Type,
	pos:  Vec3,
	rot:  Vec3, // Euler angles in degrees
	scale: Vec3,
}

Map :: struct {
	objects: [dynamic]Map_Object,
}

save_map :: proc(filename: string, m: Map) -> bool {
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	for obj in m.objects {
		type_int := int(obj.type)
		fmt.sbprintf(&sb, "%d %f %f %f %f %f %f %f %f %f\n", 
			type_int, 
			obj.pos.x, obj.pos.y, obj.pos.z,
			obj.rot.x, obj.rot.y, obj.rot.z,
			obj.scale.x, obj.scale.y, obj.scale.z,
		)
	}

	return write_entire_file(filename, transmute([]byte)strings.to_string(sb))
}

load_map :: proc(filename: string) -> (Map, bool) {
	data, ok := read_entire_file(filename)
	if !ok {
		return {}, false
	}
	defer delete(data)

	content := string(data)
	m: Map

	it := content
	for line in strings.split_iterator(&it, "\n") {
		line := strings.trim_space(line)
		if len(line) == 0 {
			continue
		}

		parts := strings.fields(line)
		defer delete(parts)
		
		if len(parts) >= 10 {
			obj: Map_Object
			
			type_int, _ := strconv.parse_int(parts[0])
			obj.type = Map_Object_Type(type_int)
			
			obj.pos.x, _ = strconv.parse_f32(parts[1])
			obj.pos.y, _ = strconv.parse_f32(parts[2])
			obj.pos.z, _ = strconv.parse_f32(parts[3])
			
			obj.rot.x, _ = strconv.parse_f32(parts[4])
			obj.rot.y, _ = strconv.parse_f32(parts[5])
			obj.rot.z, _ = strconv.parse_f32(parts[6])
			
			obj.scale.x, _ = strconv.parse_f32(parts[7])
			obj.scale.y, _ = strconv.parse_f32(parts[8])
			obj.scale.z, _ = strconv.parse_f32(parts[9])
			
			append(&m.objects, obj)
		}
	}

	return m, true
}
