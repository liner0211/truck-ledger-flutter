# 与 TheosUIApp/TruckLedger 一致：供 deploy.sh / debug.sh 读取默认设备 IP。
THEOS_DEVICE_IP ?= 192.168.0.129

FLUTTER ?= flutter

.PHONY: clean ios-build package ipa ipa-one deb-install-one apk-install-one machine-env-example

clean:
	$(FLUTTER) clean

ios-build:
	$(FLUTTER) build ios --release --no-codesign

# 打越狱 deb（脚本内会执行 flutter build；需 macOS + Xcode）
package:
	./package_deb.sh

# 打 ipa 容器（Payload + zip；签名需自行处理）
ipa:
	./package_ipa.sh

# 一键：CI 拉取 Runner.app → ipa（本机需 gh）
ipa-one:
	./one_click_ipa.sh

# 一键：CI 拉取 → 打 deb → SSH 安装（本机需 gh、paramiko、.device.env 或 DEVICE_PASS）
deb-install-one:
	./one_click_deb_install.sh

# 一键：本机 Release APK + adb 安装（需 adb、FLUTTER_BIN_PATH）
apk-install-one:
	./one_click_apk_install.sh

# 首次克隆后：复制本机配置模板（若已存在则跳过）
machine-env-example:
	@if [ -f dev/machine.env ]; then echo "dev/machine.env 已存在"; else cp dev/machine.env.example dev/machine.env && echo "已创建 dev/machine.env，请编辑后使用一键脚本或 VS Code 任务"; fi
