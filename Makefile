# 越狱 SSH 设备默认 IP（供 deploy.sh / debug.sh 读取；兼容旧变量 THEOS_DEVICE_IP）。
DEVICE_IP_DEFAULT ?= 192.168.0.129
THEOS_DEVICE_IP ?= $(DEVICE_IP_DEFAULT)

.PHONY: ship ipa-one deb-install-one apk-install-one machine-env-example server-deploy

# 一键总控：push → 等 CI 编译/上传/部署 → 可选装包（见 ./one_click_ship.sh -h）
ship:
	./one_click_ship.sh

# 一键：从 CI / 生产下载 IPA（禁止本机编译）
ipa-one:
	./one_click_ipa.sh

# 一键：从 CI / 生产下载 deb → SSH 安装
deb-install-one:
	./one_click_deb_install.sh

# 一键：从 CI / 生产下载 APK → adb 安装
apk-install-one:
	./one_click_apk_install.sh

# 一键：rsync 部署 server-php（需 SERVER_*，见 machine.env.example）
server-deploy:
	./one_click_server_deploy.sh

# 首次克隆后：复制本机配置模板（若已存在则跳过）
machine-env-example:
	@if [ -f dev/machine.env ]; then echo "dev/machine.env 已存在"; else cp dev/machine.env.example dev/machine.env && echo "已创建 dev/machine.env，请编辑后使用一键脚本或 VS Code 任务"; fi
