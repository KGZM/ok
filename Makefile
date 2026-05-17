# kak-emporium — top-level build
#
# Builds all components for the host architecture and stages them into
# a single dist/local/ tree suitable for running kak directly.
#
# Usage:
#   make              — build everything for the host arch
#   make kak          — build kak only
#   make kak-lsp      — build kak-lsp only
#   make clean        — remove dist/
#   make run          — launch kak from dist/local/

HOST_ARCH != uname -m | sed 's/x86_64/x86_64/;s/aarch64/aarch64/'
HOST_TARGET = $(HOST_ARCH)-linux

KAK_ZIG_TARGET_x86_64 = x86_64-linux-musl
KAK_ZIG_TARGET_aarch64 = aarch64-linux-musl
KAK_ZIG_TARGET = $(KAK_ZIG_TARGET_$(HOST_ARCH))

DIST = dist/local

.PHONY: all kak kak-lsp kak-tree-sitter clean run grammars

all: kak kak-lsp kak-tree-sitter
	@echo ""
	@echo "kak-emporium dist ready at $(DIST)/"
	@echo "Run with: make run"

kak:
	$(MAKE) -C kak package \
		DIST_TARGET=$(HOST_TARGET) \
		CXX="zig c++ -target $(KAK_ZIG_TARGET)"
	rm -rf $(DIST)/bin/kak $(DIST)/share/kak
	mkdir -p $(DIST)/bin $(DIST)/share
	cp -r kak/dist/$(HOST_TARGET)/bin/kak $(DIST)/bin/
	cp -r kak/dist/$(HOST_TARGET)/share/kak $(DIST)/share/

kak-lsp:
	$(MAKE) -C kak-lsp package DIST_TARGET=$(HOST_TARGET)
	rm -rf $(DIST)/bin/kak-lsp $(DIST)/share/kak-lsp
	mkdir -p $(DIST)/bin $(DIST)/share
	cp -r kak-lsp/dist/$(HOST_TARGET)/bin/kak-lsp $(DIST)/bin/
	cp -r kak-lsp/dist/$(HOST_TARGET)/share/kak-lsp $(DIST)/share/

kak-tree-sitter:
	$(MAKE) -C kak-tree-sitter package DIST_TARGET=$(HOST_TARGET)
	rm -rf $(DIST)/bin/kak-tree-sitter $(DIST)/bin/ktsctl $(DIST)/share/kak-tree-sitter
	mkdir -p $(DIST)/bin $(DIST)/share
	cp -r kak-tree-sitter/dist/$(HOST_TARGET)/bin/kak-tree-sitter \
	      kak-tree-sitter/dist/$(HOST_TARGET)/bin/ktsctl \
	      $(DIST)/bin/
	cp -r kak-tree-sitter/dist/$(HOST_TARGET)/share/kak-tree-sitter $(DIST)/share/

XDG_RUNTIME_DIR ?= /tmp/kak-runtime

run:
	@test -x $(DIST)/bin/kak || { echo "run 'make' first"; exit 1; }
	@mkdir -p $(XDG_RUNTIME_DIR)
	KAKOUNE_RUNTIME=$(CURDIR)/$(DIST)/share/kak \
	KAK_TREE_SITTER_RUNTIME=$(CURDIR)/$(DIST)/share/kak-tree-sitter \
	XDG_RUNTIME_DIR=$(XDG_RUNTIME_DIR) \
	XDG_DATA_HOME=$(CURDIR)/$(DIST)/share \
	CC="zig cc" \
	PATH=$(CURDIR)/$(DIST)/bin:$$PATH \
	$(DIST)/bin/kak -E "source $(CURDIR)/kakrc" $(FILE)

grammars:
	@mkdir -p $(XDG_RUNTIME_DIR)
	XDG_RUNTIME_DIR=$(XDG_RUNTIME_DIR) CC="zig cc" \
	PATH=$(CURDIR)/$(DIST)/bin:$$PATH \
	ktsctl sync rust bash python toml yaml

clean:
	rm -rf dist/
