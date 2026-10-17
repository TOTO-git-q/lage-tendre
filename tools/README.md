# 本地工具

从仓库根目录运行。Python 入口优先使用 `GODOT`，然后查找 `.tools/godot.exe`、`.tools/godot` 和 PATH 中的 `godot` / `godot4`。本地工具不下载引擎或安装依赖。GitHub CI 显式使用 `bash tools/setup_godot.sh --download` 下载指定的 Godot 4.7.2 Linux 引擎；不加该选项仍使用已安装版本。

| 命令 | 用途 |
| --- | --- |
| `python tools/sync_core.py` | 同步共享代码、插件、资源和 API 文档，生成 SHA-256 清单 |
| `python tools/sync_core.py --check` | 只读检查同步副本 |
| `python tools/run_tests.py` | 静音运行游戏、插件和写谱器测试，日志在 dist/test-results |
| `python tools/run_tests.py --suite charter --visual` | 写谱器离屏视觉检查；Linux 需 xvfb |
| `python tools/build_release.py` | 构建两个 Windows ZIP，校验完整性与哈希，不发布 |
| `python tools/smoke_release.py` | 全新解压后检查自动演奏截图、写谱器歌曲列表、MCP 和预览 |
| `python tools/public_audit.py` | 扫描禁用内容、个人路径、凭据样式、音频和文件大小 |
| `python tools/validate_fan_chart.py [slug ...]` | 检查社区谱面结构、许可、真实 ChartLib 与全 PERFECT 自动演奏；`--changed base...head` 仅检查变更目录 |
| `python tools/test_validate_fan_chart.py` | 生成原创临时夹具，验证投稿检查器及插件不执行边界 |
| `python tools/verify_fan_charts.py` | 临时歌曲根目录中的游戏/写谱器集成、离屏分组截图与发布复制检查 |

Windows 缺少创建符号链接权限时，两个套件会保留失败：plugin_demo_app_test 的一项链接夹具断言，以及 song_plugin_session_test 的四项链接夹具断言。断言不会跳过或算作通过。已有证书存储提示和特定写谱器退出诊断保留在日志；分类见 test_results.py。

数值及确定性截图采集、对比命令见 game/tests/baselines/README.md。图像比较与发布冒烟检查使用已安装的 Pillow，其他工具使用标准库。Godot 自动运行采用 Dummy 音频和 headless 或离屏窗口。

可选 Claude CLI 可用 `CLAUDE_CLI` 指定；否则查找当前用户 APPDATA 下的 npm 安装，再使用 PATH 中的 claude。无需 CLI 即可手工写谱或使用 MCP。
