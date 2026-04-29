PREFIX     ?= /usr/local
BIN_DIR    := $(PREFIX)/bin
HELPER_BIN := $(BIN_DIR)/karabiner-cjk-helper
KICKER_BIN := $(BIN_DIR)/karabiner-cjk-kicker
TRIGGER_BIN:= $(BIN_DIR)/karabiner-cjk-trigger
PLIST      := $(HOME)/Library/LaunchAgents/org.dilyin.karabiner-cjk-helper.plist
LABEL      := org.dilyin.karabiner-cjk-helper
UID        := $(shell id -u)

.PHONY: all build install uninstall reload clean

all: build

build: build/karabiner-cjk-helper build/karabiner-cjk-kicker build/karabiner-cjk-trigger

build/karabiner-cjk-helper: src/karabiner-cjk-helper.swift
	@mkdir -p build
	swiftc -O -o $@ $<

build/karabiner-cjk-kicker: src/karabiner-cjk-kicker.swift
	@mkdir -p build
	swiftc -O -framework AppKit -o $@ $<

build/karabiner-cjk-trigger: src/karabiner-cjk-trigger.c
	@mkdir -p build
	clang -Os -o $@ $<

install: build install-binaries install-agent

install-binaries: build
	sudo install -m 755 build/karabiner-cjk-helper  $(HELPER_BIN)
	sudo install -m 755 build/karabiner-cjk-kicker  $(KICKER_BIN)
	sudo install -m 755 build/karabiner-cjk-trigger $(TRIGGER_BIN)

install-agent:
	mkdir -p $(HOME)/Library/LaunchAgents $(HOME)/Library/Logs
	cp launchd/org.dilyin.karabiner-cjk-helper.plist $(PLIST)
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null || true
	launchctl bootstrap gui/$(UID) $(PLIST)

reload:
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null || true
	launchctl bootstrap gui/$(UID) $(PLIST)

uninstall:
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null || true
	rm -f $(PLIST)
	sudo rm -f $(HELPER_BIN) $(KICKER_BIN) $(TRIGGER_BIN)
	rm -f /tmp/karabiner-cjk-helper.sock

clean:
	rm -rf build
