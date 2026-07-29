APP      := ClaudeUsageBuddy
BUNDLE   := dist/$(APP).app
BINARY   := .build/release/$(APP)

# Ad-hoc signing, deliberately.
#
# The app reads nothing but local files, so it never needs a keychain grant — and
# without one there is no reason to maintain a signing certificate. Ad-hoc keeps the
# build free of any keychain access at all, including at sign time.
.PHONY: all build bundle run install clean kill

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(BINARY)" "$(BUNDLE)/Contents/MacOS/$(APP)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
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

clean:
	rm -rf .build dist
