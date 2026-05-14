APP_NAME := Markee
APP_BUNDLE := $(APP_NAME).app
BIN := .build/release/$(APP_NAME)
CONFIG := release

INSTALLED_BUNDLE := /Applications/$(APP_BUNDLE)
VENDOR_SENTINEL := Resources/web/vendor/.fetched

.PHONY: all build app run clean fetch-vendor install install-cli icon test test-swift test-js

all: app

build:
	swift build -c $(CONFIG)

icon:
	@./scripts/build-icon.sh

# Sentinel-based vendor fetch: first build pulls libs, subsequent builds skip.
# `make clean` nukes the whole vendor tree to force a refetch.
$(VENDOR_SENTINEL):
	@./scripts/fetch-vendor.sh
	@touch $@

fetch-vendor: $(VENDOR_SENTINEL)

app: $(VENDOR_SENTINEL) build icon
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BIN) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	cp -R Resources/web $(APP_BUNDLE)/Contents/Resources/
	cp -R Resources/cli $(APP_BUNDLE)/Contents/Resources/
	cp LICENSE $(APP_BUNDLE)/Contents/Resources/LICENSE
	cp THIRD-PARTY-NOTICES.md $(APP_BUNDLE)/Contents/Resources/THIRD-PARTY-NOTICES.md
	# Ad-hoc codesign so WKWebView and TCC don't barf
	codesign --force --deep --sign - $(APP_BUNDLE) 2>/dev/null || true
	@echo "Built $(APP_BUNDLE)"
	@if [ -L "$(INSTALLED_BUNDLE)" ] || [ -d "$(INSTALLED_BUNDLE)" ]; then \
		echo "Syncing to $(INSTALLED_BUNDLE)..."; \
		rm -rf "$(INSTALLED_BUNDLE)"; \
		cp -R $(APP_BUNDLE) "$(INSTALLED_BUNDLE)"; \
		/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$(INSTALLED_BUNDLE)"; \
	fi

install: app
	@osascript -e 'tell application "Markee" to quit' 2>/dev/null || true
	rm -rf "$(INSTALLED_BUNDLE)"
	cp -R $(APP_BUNDLE) "$(INSTALLED_BUNDLE)"
	/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$(INSTALLED_BUNDLE)"
	@echo "Installed $(INSTALLED_BUNDLE)"

run: app
	open $(APP_BUNDLE)

install-cli: app
	@if [ -w /usr/local/bin ]; then \
		ln -sf "$$(pwd)/$(APP_BUNDLE)/Contents/Resources/cli/markee" /usr/local/bin/markee; \
		echo "Installed /usr/local/bin/markee"; \
	else \
		echo "Need write access to /usr/local/bin. Try: sudo make install-cli"; \
		exit 1; \
	fi

test: test-swift test-js

test-swift:
	swift test

test-js:
	node --test Tests/util.test.js

clean:
	swift package clean
	rm -rf .build $(APP_BUNDLE) Resources/web/vendor
