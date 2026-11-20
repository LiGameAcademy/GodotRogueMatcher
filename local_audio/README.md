# 可选本地音乐（不进入公开子模块）

公开游戏仓库默认没有背景音乐。将自己有权使用的 MP3 放到课程私有仓库，不要放进本目录：

`D:\GodotProject\laoli_gamedev_godot4_course\projects\godot-rogue-matcher\local_audio\gameplay.mp3`

该目录在公开子模块 `godot-rogue-matcher/` 之外，由课程仓库管理。Game 场景启动后，GameMusic 按工程目录的 `../local_audio/gameplay.mp3` 直接读取文件，不经过 Godot 导入。文件缺失时不报错、不阻止游戏。只接受 MP3 或 Ogg Vorbis；也可在 GameMusic 的 `local_path` 指定 `res://` 或其他绝对路径。

课程仓库的 `.gitignore` 已忽略 `*.mp3`，这是为了避开 Gitee 大文件配额。因此音乐留在这台机器的私有目录中，不会进入公开子模块，也不会随课程仓库提交。私有并不取消音乐许可：发行、教程视频和游戏内署名仍须单独满足授权。

本目录除本文外全部被公开仓库忽略。公开导出预设另外排除了 `local_audio/*`。工程外的文件本来就不会打进包；含音乐的授权发行须把文件纳入该版本的资源并单独检查打包结果，导出后在干净环境实测。

采用试听音乐 C 时：来源为 Eric Matyas 的 Puzzle Dreams，https://soundimage.org/puzzle-music/ 。它不是 CC0，按 Soundimage International Public License 及作者署名指引执行：https://soundimage.org/sample-page/ 、https://soundimage.org/attribution-info/ 。在游戏内加入 “Music: Puzzle Dreams by Eric Matyas — www.soundimage.org” 等满足许可的署名，教程视频同样按指引处理，不能只写仓库 README。当前尚未制作音乐署名 UI，也未复制音乐 C，不作为含音乐版本发行。

本次只提供可选加载入口；循环由独占流资源启用，不代表接缝已经无缝修复。音乐增益 0.5、使用 Music 总线，跟随已有 Master 总音量；音乐在暂停面板期间继续播放，场景释放即停止。不得把本地音频或凭证强制 `git add -f` 进公开仓库。
