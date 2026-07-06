SHELL := /bin/bash
DERIVED_DATA := .build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/Debug/GaplessPaste.app
XCODEBUILD := xcodebuild -project GaplessPaste.xcodeproj -scheme GaplessPaste \
	-destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA)

.PHONY: gen build test run dev clean

# 从 project.yml 重新生成 GaplessPaste.xcodeproj（xcodeproj 不入库）
gen:
	xcodegen

build: gen
	set -o pipefail && $(XCODEBUILD) -configuration Debug build | xcbeautify

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
	rm -rf $(DERIVED_DATA) GaplessPasteCore/.build GaplessPaste.xcodeproj
