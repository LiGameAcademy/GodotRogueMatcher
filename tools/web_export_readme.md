# 本地Web基线构建

在Godot工程目录执行，传入本机Godot 4.7.2控制台程序路径；需要对应版本的Web导出模板。

```powershell
./tools/export_web.ps1 -GodotPath '你的Godot控制台程序完整路径'
```

默认在已忽略的production目录中创建带时间的新目录、ZIP、导出日志和构建JSON；不覆盖旧包。也可用-BuildName指定未使用过的英文名称。脚本验证退出码、导出错误和四项核心文件，ZIP根目录是index.html。

UI里程碑本机验收可加`-BuildMode Debug`，保留F7快速进入技能选择、F6固定爆炸样本；默认仍为Release。Debug用于方便检查交互，不作为正常节奏数据或公开发行包。每个里程碑分别保存目录，以localhost链接打开；不要覆盖正在试玩的旧包。

用本机Python的HTTP服务查看构建目录，不要双击HTML使用file://：

```powershell
python -m http.server 8765 --bind 127.0.0.1 --directory 'production/实际构建目录名'
```

然后打开http://127.0.0.1:8765/，Ctrl+C停止服务。服务只监听本机，不部署到互联网。不要把日志、源码或整个production目录作为HTML5游戏包上传。

运行基线使用Compatibility、单线程、非PWA；不要求COOP/COEP头。F6/F7仅在调试构建有效，Release保留F8快放/F9受政策限制的跳过。Web预设排除项目测试、工具、文档、GUT及CoreSystem演示/测试，保留插件运行模块与中文字体。

浏览器设置通过现有CoreSystem ConfigManager保存到user://，浏览器清除网站数据或禁用持久存储会影响保留；本局刷新重开，不支持续局。中文默认字体与鸣谢在assets/fonts目录，导出包另附许可文件。

当前是本地技术基线，尚未上传itch.io；正式更新前仍需验收跨浏览器、嵌入、完整单局与新手流程。导出不等于发布。
