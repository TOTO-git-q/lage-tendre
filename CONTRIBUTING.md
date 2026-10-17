# 参与开发

欢迎提交问题和改进。报告问题时说明平台、Godot 版本、复现步骤、预期结果和实际结果。附日志前移除账号、密钥和本机路径。

在 `game/` 修改共享代码，运行 `python tools/sync_core.py` 更新写谱器副本。保持改动集中；修改判定或评分时说明目的、兼容性和测试依据。

提交前运行 `python tools/run_tests.py`。涉及渲染或发布时，再运行相关离屏检查或发布冒烟测试，报告实际结果和未验证项。Windows 符号链接权限导致的已知失败应如实保留。

代码及普通随附原创资源贡献按 MIT 提供。不要提交个人游玩日志、凭据、缓存或构建输出。

## 社区谱面 / Fan-made charts

按 [社区投稿指南](songs/fan-made/README.md) 将每个投稿放入独立的 `songs/fan-made/<slug>/`，不改共享索引。提交表示你有权贡献该谱面数据，并同意以 [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) 授权；允许的更宽松许可可作为额外授权。音频与封面保留各自标注的许可，必须在 `info.json` 和 `CREDITS.md` 中列出作者、许可条款及对应资源的授权证据。

禁止没有允许再分发许可的商业歌曲。购买、在线播放或游戏内可用并不构成再分发授权。从 osu! 或其他游戏谱面移植时，必须署名原谱师，并提供原谱链接和原谱师允许移植的 `source.permission_url`。投稿前运行验证器并亲自试玩；脚本插件需维护者人工审核。自动验证无法证明权利归属或移植许可的真实性。

By submitting a fan chart, you confirm your right to contribute its data and grant CC BY-SA 4.0 under these terms. An allowed more permissive chart licence may provide an additional grant. Audio and covers keep their stated licences and require asset-specific redistribution evidence and attribution. Do not submit unlicensed commercial songs. Conversions from osu! or other games require the original mapper's permission link in `source.permission_url`. Run the validator and play your chart yourself before submitting. Script plugins and rights evidence require maintainer review. Code remains MIT licensed.
