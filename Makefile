APPS_DIR  ?= $(HOME)/Applications
BIN_DIR   ?= $(HOME)/.local/bin
AGENTS    := $(HOME)/Library/LaunchAgents
# A stable signing identity keeps the Accessibility grant across rebuilds; ad-hoc ("-") re-prompts each time.
SIGN_ID   ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID|Panespace Local Signing/ {print $$2; exit}')
ifeq ($(SIGN_ID),)
SIGN_ID   := -
endif
# ARCHS="arm64 x86_64" builds a universal app (Apple Silicon and Intel); empty = this Mac's architecture only.
ARCHS     ?=
ARCH_FLAGS := $(foreach a,$(ARCHS),--arch $(a))
BIN_PATH   = $(if $(ARCHS),$(shell swift build -c release $(ARCH_FLAGS) --show-bin-path),.build/release)
VERSION   := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
BUILD_NUM := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)
REPO      ?= panelab/panespace
# Sparkle (auto-updates): its tools come with the Swift package; the framework ships inside Panespace.app.
SPARKLE_BIN = .build/artifacts/sparkle/Sparkle/bin
SPARKLE_FW  = $(firstword $(wildcard $(BIN_PATH)/Sparkle.framework) \
                $(wildcard .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-*/Sparkle.framework))
# The private half: from the login Keychain (`make sparkle-keys`), or a file (CI: SPARKLE_KEY_FILE=path).
SPARKLE_KEY_FILE ?=
# The release signing key's public half (`make sparkle-keys`). Without it, the app builds but never updates.
SPARKLE_PUBKEY = $(strip $(if $(wildcard Resources/sparkle-public-key),$(shell cat Resources/sparkle-public-key)))

.PHONY: build test icon app dist install uninstall login-item caps-login-item no-login-item clean cert sparkle-keys

build:
	swift build -c release $(ARCH_FLAGS)

# Once per Mac: a local signing identity, so rebuilds keep the Accessibility grant (scripts/make-cert.sh).
cert:
	scripts/make-cert.sh

test:
	swift test

# Regenerate Resources/AppIcon.icns (and the README's AppIcon.png) from scripts/make-icon.swift.
icon:
	rm -rf .build/AppIcon.iconset && mkdir -p .build/AppIcon.iconset
	swift scripts/make-icon.swift .build/AppIcon.png
	swift scripts/make-icon.swift .build/AppIcon-small.png small
	for s in 16 32 128 256 512; do \
	  sips -z $$s $$s .build/AppIcon.png --out .build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
	  sips -z $$((s*2)) $$((s*2)) .build/AppIcon.png --out .build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	# 16 and 32 px come from the bold variant (64 px and up keep the fine one).
	for f in 16x16:16 16x16@2x:32 32x32:32; do \
	  sips -z $${f#*:} $${f#*:} .build/AppIcon-small.png --out .build/AppIcon.iconset/icon_$${f%:*}.png >/dev/null; \
	done
	iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
	sips -z 512 512 .build/AppIcon.png --out Resources/AppIcon.png >/dev/null

# $(call bundle,Name,executable,plist[,icon][,sparkle]): build Name.app around the built executable and sign it.
# With `sparkle`, Sparkle.framework goes into Contents/Frameworks (signed inside-out first) and the release key into
# Info.plist.
define bundle
	rm -rf $(1).app
	mkdir -p $(1).app/Contents/MacOS $(1).app/Contents/Resources
	cp $(BIN_PATH)/$(2) $(1).app/Contents/MacOS/$(2)
	cp Resources/$(3) $(1).app/Contents/Info.plist
	$(if $(4),cp Resources/$(4) $(1).app/Contents/Resources/)
	$(if $(5),$(call embed_sparkle,$(1)))
	codesign --force --sign "$(SIGN_ID)" --identifier app.panespace.$(1) $(1).app
endef

define embed_sparkle
	@test -n "$(SPARKLE_FW)" || { echo "Sparkle.framework not found: run swift build first"; exit 1; }
	mkdir -p $(1).app/Contents/Frameworks
	ditto "$(SPARKLE_FW)" $(1).app/Contents/Frameworks/Sparkle.framework
	for p in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do \
	  f=$(1).app/Contents/Frameworks/Sparkle.framework/Versions/B/$$p; \
	  if [ -e "$$f" ]; then codesign --force --sign "$(SIGN_ID)" --preserve-metadata=entitlements "$$f" || exit 1; fi; \
	done
	codesign --force --sign "$(SIGN_ID)" $(1).app/Contents/Frameworks/Sparkle.framework
	$(if $(SPARKLE_PUBKEY),/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(SPARKLE_PUBKEY)" $(1).app/Contents/Info.plist,@echo "note: no Resources/sparkle-public-key so this build never checks for updates (make sparkle-keys)")
endef

# $(call agent,Name,executable): launchd agent that starts Name.app at login.
define agent
	mkdir -p $(AGENTS)
	printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '<key>Label</key><string>app.panespace.$(1)</string>' \
	  '<key>ProgramArguments</key><array><string>$(APPS_DIR)/$(1).app/Contents/MacOS/$(2)</string></array>' \
	  '<key>RunAtLoad</key><true/>' \
	  '<key>AssociatedBundleIdentifiers</key><string>app.panespace.$(1)</string>' \
	  '<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>' \
	  '<key>ProcessType</key><string>Interactive</string>' \
	  '<key>StandardErrorPath</key><string>$(HOME)/Library/Logs/$(2).log</string>' \
	  '</dict></plist>' > $(AGENTS)/app.panespace.$(1).plist
	launchctl bootout gui/$$(id -u) $(AGENTS)/app.panespace.$(1).plist 2>/dev/null || true
	launchctl bootstrap gui/$$(id -u) $(AGENTS)/app.panespace.$(1).plist
endef

app: build
	$(call bundle,Panespace,panespace,Info.plist,AppIcon.icns,sparkle)
	$(call bundle,Caps,caps,Caps-Info.plist)
	@echo "built Panespace.app and Caps.app (signed: $(SIGN_ID))"

# Once per project, on the Mac that makes releases: the EdDSA key that signs updates. The private half goes into the
# login Keychain (back it up: `generate_keys -x file`); the public half into Resources/sparkle-public-key (commit it).
sparkle-keys:
	swift package resolve
	$(SPARKLE_BIN)/generate_keys
	$(SPARKLE_BIN)/generate_keys -p > Resources/sparkle-public-key
	@echo "public key in Resources/sparkle-public-key; commit it"

# Zipped bundles for a GitHub release: dist/Panespace-$(VERSION).zip, dist/Caps-$(VERSION).zip, and dist/appcast.xml
# (the update feed, signed with the key from `make sparkle-keys`). Upload all three to the release tagged v$(VERSION).
# Bump CFBundleVersion in Resources/Info.plist for every release: Sparkle compares that number.
dist:
	@test -f Resources/sparkle-public-key || { echo "no Resources/sparkle-public-key: run make sparkle-keys first"; exit 1; }
	$(MAKE) app ARCHS="arm64 x86_64"
	rm -rf dist && mkdir -p dist/appcast
	ditto -c -k --keepParent Panespace.app dist/Panespace-$(VERSION).zip
	ditto -c -k --keepParent Caps.app dist/Caps-$(VERSION).zip
	cp dist/Panespace-$(VERSION).zip dist/appcast/
	$(SPARKLE_BIN)/generate_appcast $(if $(SPARKLE_KEY_FILE),--ed-key-file $(SPARKLE_KEY_FILE)) --download-url-prefix https://github.com/$(REPO)/releases/download/v$(VERSION)/ \
	  --link https://github.com/$(REPO) dist/appcast
	mv dist/appcast/appcast.xml dist/appcast.xml && rm -rf dist/appcast
	@echo "release v$(VERSION) (build $(BUILD_NUM)) in dist/: upload Panespace-$(VERSION).zip, Caps-$(VERSION).zip, appcast.xml"

install: app
	mkdir -p $(APPS_DIR) $(BIN_DIR)
	@# Replacing a running binary gets it killed for an invalid signature, and launchd then holds the restart
	@# back: stop it first, start it again after.
	@launchctl kill TERM gui/$$(id -u)/app.panespace.Panespace 2>/dev/null; pkill -x panespace 2>/dev/null; true
	@launchctl kill TERM gui/$$(id -u)/app.panespace.Caps 2>/dev/null; pkill -x caps 2>/dev/null; sleep 0.3; true
	rm -rf $(APPS_DIR)/Panespace.app $(APPS_DIR)/Caps.app
	cp -R Panespace.app Caps.app $(APPS_DIR)/
	ln -sf $(APPS_DIR)/Panespace.app/Contents/MacOS/panespace $(BIN_DIR)/panespace
	ln -sf $(APPS_DIR)/Caps.app/Contents/MacOS/caps $(BIN_DIR)/caps
	@launchctl kickstart -k gui/$$(id -u)/app.panespace.Panespace 2>/dev/null || true
	@launchctl kickstart -k gui/$$(id -u)/app.panespace.Caps 2>/dev/null || true
	@echo "installed $(APPS_DIR)/Panespace.app and $(APPS_DIR)/Caps.app; CLIs in $(BIN_DIR)"
	@echo "start: open $(APPS_DIR)/Panespace.app $(APPS_DIR)/Caps.app   (grant Accessibility to each when asked)"

login-item:
	$(call agent,Panespace,panespace)
	@echo "panespace now starts at login (log: ~/Library/Logs/panespace.log)"

caps-login-item:
	$(call agent,Caps,caps)
	@echo "Caps now starts at login (log: ~/Library/Logs/caps.log)"

no-login-item:
	for a in Panespace Caps; do launchctl bootout gui/$$(id -u) $(AGENTS)/app.panespace.$$a.plist 2>/dev/null; rm -f $(AGENTS)/app.panespace.$$a.plist; done; true

uninstall: no-login-item
	-$(BIN_DIR)/panespace exit 2>/dev/null
	-pkill -x caps
	rm -rf $(APPS_DIR)/Panespace.app $(APPS_DIR)/Caps.app $(BIN_DIR)/panespace $(BIN_DIR)/caps

clean:
	rm -rf .build dist Panespace.app Caps.app

# End-to-end: drives the running daemon with real test windows on a workspace of its own ("e2e") and checks the
# screen against the model. Takes about a minute; don't use the Mac meanwhile.
e2e:
	mkdir -p .build/e2e
	swiftc -O scripts/e2e/testwin.swift -o .build/e2e/testwin
	swiftc -O scripts/e2e/zorder.swift -o .build/e2e/zorder
	cp scripts/e2e/e2e.py .build/e2e/ && python3 -I .build/e2e/e2e.py
.PHONY: e2e
