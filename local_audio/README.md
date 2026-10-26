# 可选本地音乐（Git不收录音频）

公开仓库默认没有背景音乐。将自己有权使用的MP3放在本目录，命名为gameplay.mp3，启动Game场景后GameMusic会加载它。也可在GameMusic场景实例的local_path指定Ogg Vorbis；缺失文件时不报错、不阻止游戏。不支持不经检查地放入其他媒体类型。

本目录除本文外全部被Git忽略（含.import旁文件）；放入文件后让Godot编辑器完成导入。Git忽略只影响上传，不控制发行包；本项目公开导出预设另外排除了local_audio/*，因此普通公开构建仍无音乐。若制作含音乐的授权发行版本，应复制导出预设后明确移除这条排除规则、保留all_resources，并检查实际打包内容；不要修改公开预设后误发音乐。导出后在干净环境实测，不依赖开发机的文件存在。

采用试听音乐C时：来源为Eric Matyas的Puzzle Dreams，https://soundimage.org/puzzle-music/ 。它不是CC0，按Soundimage International Public License及作者署名指引执行：https://soundimage.org/sample-page/ 、https://soundimage.org/attribution-info/ 。在游戏内加入“Music: Puzzle Dreams by Eric Matyas — www.soundimage.org”等满足许可的署名，教程视频同样按指引处理，不能只写仓库README。当前尚未制作音乐署名UI，也未复制音乐C到此目录，不作为含音乐版本发行。

本次只提供可选加载入口；循环由独占流资源启用，不代表接缝已经无缝修复。音乐增益0.5、使用Music总线，跟随已有Master总音量；音乐在暂停面板期间继续播放，场景释放即停止。不得把本地音频或凭证强制git add -f进公开仓库。
