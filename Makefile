APP      := ClaudeUsageBuddy
BUNDLE   := dist/$(APP).app
BINARY   := .build/release/$(APP)

# Ad-hoc signing, deliberately.
#
# The app reads nothing but local files, so it never needs a keychain grant — and
# without one there is no reason to maintain a signing certificate. Ad-hoc keeps the
# build free of any keychain access at all, including at sign time.
.PHONY: all build bundle run install clean kill icon test-burn-rate

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(BINARY)" "$(BUNDLE)/Contents/MacOS/$(APP)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	codesign --force --sign - "$(BUNDLE)"
	@echo "built $(BUNDLE)"

# Relaunch cleanly; the app is an accessory so there is no Dock icon to click.
run: bundle kill
	open "$(BUNDLE)"

kill:
	-@pkill -x $(APP) 2>/dev/null || true

install: bundle kill
	rm -rf "/Applications/$(APP).app"
	cp -R "$(BUNDLE)" /Applications/
	open "/Applications/$(APP).app"

# Synthetic-series checks for the burn-rate maths. There is no test target because
# there is no Xcode here, so this compiles the real BurnRate.swift into a small
# assertion runner — no copied logic to drift out of sync.
# Compiles the whole Usage layer rather than a hand-picked file list. Three features
# landed in parallel and cross-linked these types (Theme now references ModelUsage,
# UsageSnapshot references UsageProbe.Weekly), so an explicit list went stale on every
# merge. The point is that the real sources are built, not copies of the logic.
test-burn-rate:
	swiftc -O $(wildcard Sources/ClaudeUsageBuddy/Usage/*.swift) \
	       Sources/ClaudeUsageBuddy/UI/Theme.swift \
	       Tools/burn-rate-tests.swift -o /tmp/cub-burn-rate-tests
	/tmp/cub-burn-rate-tests
	/tmp/cub-burn-rate-tests

# Regenerates the icon from the sprite in Buddy.swift, so the two never diverge.
icon:
	swiftc -O Sources/ClaudeUsageBuddy/UI/Buddy.swift Tools/make-icon.swift -o /tmp/cub-mkicon
	/tmp/cub-mkicon Resources
	iconutil --convert icns --output Resources/AppIcon.icns Resources/AppIcon.iconset
	rm -rf Resources/AppIcon.iconset
	@echo "regenerated Resources/AppIcon.icns"

clean:
	rm -rf .build dist
