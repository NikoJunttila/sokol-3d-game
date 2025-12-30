// Implementations of `read_entire_file` and `write_entire_file` using the libc
// stuff emscripten exposes. You can read the files that get bundled by
// `--preload-file assets` in `build_web` script.

#+build wasm32, wasm64p32

package web_support

import "base:runtime"
import "core:log"
import "core:c"
import "core:strings"
import libc "vendor:libc"

SEEK_SET :: 0
SEEK_CUR :: 1
SEEK_END :: 2

// Similar to raylib's LoadFileData
read_entire_file :: proc(name: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool) {
	if name == "" {
		log.error("No file name provided")
		return
	}

	file := libc.fopen(strings.clone_to_cstring(name, context.temp_allocator), "rb")

	if file == 0 {
		log.errorf("Failed to open file %v", name)
		return
	}

	defer libc.fclose(file)

	libc.fseek(file, 0, SEEK_END)
	size := libc.ftell(file)
	libc.fseek(file, 0, SEEK_SET)

	if size <= 0 {
		log.errorf("Failed to read file %v", name)
		return
	}

	data_err: runtime.Allocator_Error
	data, data_err = make([]byte, size, allocator, loc)

	if data_err != nil {
		log.errorf("Error allocating memory: %v", data_err)
		return
	}

	read_size := libc.fread(raw_data(data), 1, c.size_t(size), file)

	if read_size != c.size_t(size) {
		log.warnf("File %v partially loaded (%i bytes out of %i)", name, read_size, size)
	}

	log.debugf("Successfully loaded %v", name)
	return data, true
}

// Similar to raylib's SaveFileData.
//
// Note: This can save during the current session, but I don't think you can
// save any data between sessions. So when you close the tab your saved files
// are gone. Perhaps you could communicate back to emscripten and save a cookie.
// Or communicate with a server and tell it to save data.
write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	if name == "" {
		log.error("No file name provided")
		return
	}

	file := libc.fopen(strings.clone_to_cstring(name, context.temp_allocator), truncate ? "wb" : "ab")
	defer libc.fclose(file)

	if file == 0 {
		log.errorf("Failed to open '%v' for writing", name)
		return
	}

	bytes_written := libc.fwrite(raw_data(data), 1, len(data), file)

	if bytes_written == 0 {
		log.errorf("Failed to write file %v", name)
		return
	} else if bytes_written != len(data) {
		log.errorf("File partially written, wrote %v out of %v bytes", bytes_written, len(data))
		return
	}
	
	log.debugf("File written successfully: %v", name)
	return true
}