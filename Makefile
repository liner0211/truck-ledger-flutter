.PHONY: ship server-deploy machine-env-example

# 一键总控：push → 等 CI 编译/上传/部署（见 ./one_click_ship.sh -h）
ship:
	./one_click_ship.sh

# 一键：rsync 部署 server-php（需 SERVER_*，见 machine.env.example）
server-deploy:
	./one_click_server_deploy.sh

# 首次克隆后：复制本机配置模板（若已存在则跳过）
machine-env-example:
	@if [ -f dev/machine.env ]; then echo "dev/machine.env 已存在"; else cp dev/machine.env.example dev/machine.env && echo "已创建 dev/machine.env，请编辑后使用一键脚本或 VS Code 任务"; fi
