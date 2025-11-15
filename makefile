.PHONY: setup hot release web run clean update-sokol compile-sokol help

# Default target
help:
	@echo "Available targets:"
	@echo "  setup         - Download and compile Sokol (first time setup)"
	@echo "  hot           - Build hot reload game DLL and executable"
	@echo "  hot-run       - Build and run hot reload build"
	@echo "  release       - Build release executable"
	@echo "  release-run   - Build and run release executable"
	@echo "  web           - Build web version"
	@echo "  web-run       - Build web and start local server"
	@echo "  update-sokol  - Update Sokol bindings and shader compiler"
	@echo "  compile-sokol - Compile Sokol C libraries"
	@echo "  clean         - Remove build directory"

# First time setup
setup:
	python3 build.py -update-sokol -compile-sokol

# Hot reload build
hot:
	python3 build.py -hot-reload

hot-run:
	python3 build.py -hot-reload -run

# Release build
release:
	python3 build.py -release

release-run:
	python3 build.py -release -run

# Web build
web:
	@python3 build.py -web
	@echo ""
	@echo "=========================================="
	@echo "Web build complete! Build located in: build/web"
	@echo ""
	@echo "To run the web build:"
	@echo "  make web-run"
	@echo ""
	@echo "Or manually:"
	@echo "  cd build/web"
	@echo "  python3 -m http.server 8000"
	@echo "  Then open http://localhost:8000 in your browser"
	@echo "=========================================="
	@echo ""

web-run: web
	@echo ""
	@echo "Starting web server on http://localhost:8000"
	@echo "Open your browser to: http://localhost:8000"
	@echo "Press Ctrl+C to stop the server"
	@echo ""
	@cd build/web && python3 -m http.server 8000

# Debug builds
hot-debug:
	python3 build.py -hot-reload -debug

release-debug:
	python3 build.py -release -debug

release-debug-run:
	python3 build.py -release -debug -run

web-debug:
	python3 build.py -web -debug

# OpenGL variants
hot-gl:
	python3 build.py -hot-reload -gl

release-gl:
	python3 build.py -release -gl

# Sokol management
update-sokol:
	python3 build.py -update-sokol

compile-sokol:
	python3 build.py -compile-sokol

# Clean build artifacts
clean:
	rm -rf build/
	rm -f *.bin *.exe *.dll *.dylib *.so

# Convenience aliases
run: hot-run
build: hot
build-web: web
