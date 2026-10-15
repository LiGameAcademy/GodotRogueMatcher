# Web构建与0.0.2发布验收

版本来源为project.godot的application/config/version。当前是0.0.2候选版；公开入口只有实际上传并核对后才能记为0.0.2。

在Godot工程目录执行，使用Godot4.7.2控制台程序及对应Web模板：

```powershell
./tools/export_web.ps1 -GodotPath '你的Godot控制台程序完整路径' -BuildName web_0_0_2_rc1
```

默认Release，Compatibility、单线程、非PWA。production已忽略；每次选择新名称，保留目录、ZIP、日志和build.json，拒绝覆盖已有构建。ZIP根目录是index.html，附带发行说明与游戏／CoreSystem／字体许可；导出检查退出码、错误日志和四项核心文件。

构建清单记录源提交、工作区是否干净、子模块版本、规则版本、资源配置文件SHA256、PCK及ZIP哈希。配置文件指纹用于核对来源，不冒充RunSnapshot的运行时config_hash。发行包必须从干净提交导出；保留该提交和上一版0.0.1包作为回退来源。PR合并后正式发行需从最终合并提交重新导出，不能把候选包源提交改写成合并提交。

本地用HTTP服务打开实际构建目录，不要双击HTML：

```powershell
python -m http.server 8765 --bind 127.0.0.1 --directory 'production/web_0_0_2_rc1'
```

服务仅监听本机，Ctrl+C停止。Web不要求COOP/COEP头。Release不开放开发调试快捷键；F1设置、Esc暂停、F8快放、F9受政策限制的跳过仍可用。

发行验收记录Chrome/Edge、1280×720/1024×640、中英、移动、选卡确认及返回、暂停、模式切换、教学、终局重试、继续挑战和低特效的实际结果。未测项写待测，自动规则测试不冒充浏览器试玩。现有桌面完整回归见docs/o3_acceptance.md；Web单独记录。

设置与教学进度使用浏览器user://本地存储，受站点存储权限及清理影响；刷新不续局。Web关闭桌面遥测采集器，隐藏目录和导出按钮，内部命令记录不构成可下载的试玩采集支持；需分析的试玩仍用桌面版。退出浏览器无法保证最后写入，不承诺关闭时留档。无上传端点。

候选验收后，按最终合并提交构建正式包，创建0.0.2 tag/GitHub Release，再更新现有itch.io页面。分别打开公开入口核对实际版本、构建身份及操作，记录URL和哈希；若失败，恢复上一版包并保留问题记录。导出成功不等于发布成功。
