# 与 TheosUIApp/TruckLedger 一致：供 deploy.sh / debug.sh 读取默认设备 IP。
THEOS_DEVICE_IP ?= 192.168.0.129

FLUTTER ?= flutter

.PHONY: clean ios-build package ipa

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
