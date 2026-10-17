SHELL := /bin/bash
DERIVED_DATA := .build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/Debug/GaplessPaste.app
XCODEBUILD := xcodebuild -project GaplessPaste.xcodeproj -scheme GaplessPaste \
	-destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA)

.PHONY: gen build test run dev clean build-release notarize-app dmg notarize release-local

RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/GaplessPaste.app
DIST := dist
# Apple 签名/公证凭据的唯一来源（变量说明见该目录 AGENTS.md）；CI 没有这个文件，改由同名 env 提供
APPLE_SECRETS := $(HOME)/Sync/apple-developer/secrets.env
LOAD_SECRETS := if [ -f "$(APPLE_SECRETS)" ]; then set -a; source "$(APPLE_SECRETS)"; set +a; fi
# 发布版本号：CI 按 tag 传入（make build-release VERSION=1.2.3 BUILD_NUMBER=42），本地不传用 project.yml 的值
VERSION_ARGS := $(if $(VERSION),MARKETING_VERSION=$(VERSION),) $(if $(BUILD_NUMBER),CURRENT_PROJECT_VERSION=$(BUILD_NUMBER),)

# 从 project.yml 重新生成 GaplessPaste.xcodeproj（xcodeproj 不入库）
gen:
	xcodegen

build: gen
	set -o pipefail && $(XCODEBUILD) -configuration Debug build | xcbeautify

# Release 构建：Developer ID 签名 + hardened runtime + timestamp，Universal（arm64 + x86_64）。
# 签名设置在 Config/Release.xcconfig；DEVELOPMENT_TEAM 取 APPLE_TEAM_ID（secrets.env 或 CI env）
build-release: gen
	@$(LOAD_SECRETS); set -o pipefail && $(XCODEBUILD) -configuration Release build \
		ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO DEVELOPMENT_TEAM="$${APPLE_TEAM_ID:?缺 APPLE_TEAM_ID}" \
		$(VERSION_ARGS) | xcbeautify
	scripts/release/verify-app.sh $(RELEASE_APP)

# 公证 Release 产物并把票据钉进 app（Homebrew 装的是从 dmg 里拷出来的 app，它自己得带票据）
notarize-app:
	@$(LOAD_SECRETS); scripts/release/notarize.sh $(RELEASE_APP)

# 已公证的 app → dist/GaplessPaste-<version>.dmg（dmg 的签名在 notarize）
dmg:
	scripts/release/make-dmg.sh $(RELEASE_APP) $(DIST)

# 签名 dist/ 下的 dmg、公证、staple、Gatekeeper 终验（本地发版或排查用；正式发布走 CI）
notarize:
	@$(LOAD_SECRETS); for f in $(DIST)/*.dmg; do scripts/release/notarize.sh "$$f"; done

# 本地完整走一遍发布产物链路，不上传、不改 tap
release-local: build-release
	rm -rf $(DIST)
	$(MAKE) notarize-app dmg notarize

# GaplessPasteCore 纯逻辑单测
test:
	cd GaplessPasteCore && swift test

# kill 后等旧进程退出，再用 open -n 强制新实例启动：
# 普通 open 在进程刚退出时会撞上 LaunchServices 的滞留注册而报 -600。
# 需要给 app 注入环境变量时用 open -n --env KEY=value $(APP)
# （open 启动的 app 不继承 shell 环境）。
run:
	@pkill -x GaplessPaste 2>/dev/null || true
	@for i in $$(seq 1 20); do pgrep -qx GaplessPaste || break; sleep 0.1; done
	@open -n $(APP)

dev: build run

clean:
	rm -rf $(DERIVED_DATA) GaplessPasteCore/.build GaplessPaste.xcodeproj $(DIST)
