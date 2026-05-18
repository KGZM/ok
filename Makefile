# kak-emporium — top-level build
#
# Builds all components for a target architecture and stages them into
# dist/$(DIST_TARGET)/ ready to assemble into a bundle.
#
# Usage:
#   make                            — build everything for the host arch
#   make DIST_TARGET=aarch64-linux  — build everything for aarch64 (cross)
#   make x86_64                     — explicit x86_64 build
#   make aarch64                    — explicit aarch64 cross-build
#   make kak                        — kak only (respects DIST_TARGET)
#   make kak-lsp                    — kak-lsp only
#   make kak-tree-sitter            — kak-tree-sitter + grammars
#   make clean                      — remove dist/
#   make run                        — launch kak (host arch only)

HOST_ARCH != uname -m | sed 's/x86_64/x86_64/;s/aarch64/aarch64/'

# Default to host arch; override for cross-compilation.
DIST_TARGET ?= $(HOST_ARCH)-linux
DIST = dist/$(DIST_TARGET)

# kak (C++) zig cross-compilation targets — static musl.
KAK_ZIG_TARGET_x86_64-linux  = x86_64-linux-musl
KAK_ZIG_TARGET_aarch64-linux = aarch64-linux-musl
KAK_ZIG_TARGET = $(KAK_ZIG_TARGET_$(DIST_TARGET))

.PHONY: all kak kak-lsp kak-tree-sitter clean run x86_64 aarch64

# Convenience targets — build all components for the named arch.
x86_64:
	$(MAKE) DIST_TARGET=x86_64-linux all

aarch64:
	$(MAKE) DIST_TARGET=aarch64-linux all

all: kak kak-lsp kak-tree-sitter
	@echo ""
	@echo "kak-emporium dist ready at $(DIST)/"
	@echo "Run with: make run  (host arch only)"

kak:
	$(MAKE) -C kak package \
		DIST_TARGET=$(DIST_TARGET) \
		CXX="zig c++ -target $(KAK_ZIG_TARGET)"
	rm -rf $(DIST)/bin/kak $(DIST)/share/kak
	mkdir -p $(DIST)/bin $(DIST)/share
	cp -r kak/dist/$(DIST_TARGET)/bin/kak $(DIST)/bin/
	cp -r kak/dist/$(DIST_TARGET)/share/kak $(DIST)/share/

kak-lsp:
	$(MAKE) -C kak-lsp package DIST_TARGET=$(DIST_TARGET)
	rm -rf $(DIST)/bin/kak-lsp $(DIST)/share/kak-lsp
	mkdir -p $(DIST)/bin $(DIST)/share
	cp -r kak-lsp/dist/$(DIST_TARGET)/bin/kak-lsp $(DIST)/bin/
	cp -r kak-lsp/dist/$(DIST_TARGET)/share/kak-lsp $(DIST)/share/

kak-tree-sitter:
	$(MAKE) -C kak-tree-sitter package DIST_TARGET=$(DIST_TARGET)
	rm -rf $(DIST)/bin/kak-tree-sitter $(DIST)/bin/ktsctl $(DIST)/share/kak-tree-sitter
	mkdir -p $(DIST)/bin $(DIST)/share
	cp -r kak-tree-sitter/dist/$(DIST_TARGET)/bin/kak-tree-sitter \
	      kak-tree-sitter/dist/$(DIST_TARGET)/bin/ktsctl \
	      $(DIST)/bin/
	cp -r kak-tree-sitter/dist/$(DIST_TARGET)/share/kak-tree-sitter $(DIST)/share/

XDG_RUNTIME_DIR ?= /tmp/kak-runtime

run:
	@test "$(DIST_TARGET)" = "$(HOST_ARCH)-linux" || \
		{ echo "error: 'make run' only works for the host arch ($(HOST_ARCH)-linux)"; exit 1; }
	@test -x $(DIST)/bin/kak || { echo "run 'make' first"; exit 1; }
	@mkdir -p $(XDG_RUNTIME_DIR)
	KAKOUNE_RUNTIME=$(CURDIR)/$(DIST)/share/kak \
	KAK_TREE_SITTER_RUNTIME=$(CURDIR)/$(DIST)/share/kak-tree-sitter \
	XDG_RUNTIME_DIR=$(XDG_RUNTIME_DIR) \
	XDG_DATA_HOME=$(CURDIR)/$(DIST)/share \
	CC="zig cc" \
	PATH=$(CURDIR)/$(DIST)/bin:$$PATH \
	$(DIST)/bin/kak -E "source $(CURDIR)/kakrc" $(FILE)

clean:
	rm -rf dist/
