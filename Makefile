APP_NAME := Markee
APP_BUNDLE := $(APP_NAME).app
BIN := .build/release/$(APP_NAME)
CONFIG := release

.PHONY: all build app run clean fetch-vendor install-cli icon

all: app

build:
	swift build -c $(CONFIG)

icon:
	@./scripts/build-icon.sh

app: build icon
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BIN) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	cp -R Resources/web $(APP_BUNDLE)/Contents/Resources/
	cp -R Resources/cli $(APP_BUNDLE)/Contents/Resources/
	# Ad-hoc codesign so WKWebView and TCC don't barf
	codesign --force --deep --sign - $(APP_BUNDLE) 2>/dev/null || true
	@echo "Built $(APP_BUNDLE)"

run: app
	open $(APP_BUNDLE)

fetch-vendor:
	@./scripts/fetch-vendor.sh

install-cli: app
	@if [ -w /usr/local/bin ]; then \
		ln -sf "$$(pwd)/$(APP_BUNDLE)/Contents/Resources/cli/markee" /usr/local/bin/markee; \
		echo "Installed /usr/local/bin/markee"; \
	else \
		echo "Need write access to /usr/local/bin. Try: sudo make install-cli"; \
		exit 1; \
	fi

clean:
	swift package clean
	rm -rf .build $(APP_BUNDLE)
