APP      := ClaudeUsageBuddy
BUNDLE   := dist/$(APP).app
BINARY   := .build/release/$(APP)

# Signing identity.
#
# Ad-hoc signatures change on every build, which changes the app's designated
# requirement, which invalidates the keychain ACL — so macOS re-prompts for token
# access after each rebuild. A stable self-signed identity fixes that permanently.
# Create one with `make signing-identity`; falls back to ad-hoc if absent.
SIGN_NAME := Claude Usage Buddy Dev
HAVE_ID   := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -c "$(SIGN_NAME)")
SIGN_ID   := $(if $(filter 0,$(HAVE_ID)),-,$(SIGN_NAME))

.PHONY: all build bundle run install clean kill signing-identity

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(BINARY)" "$(BUNDLE)/Contents/MacOS/$(APP)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	codesign --force --sign "$(SIGN_ID)" "$(BUNDLE)"
	@echo "built $(BUNDLE)  (signed: $(SIGN_ID))"

signing-identity:
	./scripts/create-signing-identity.sh

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
