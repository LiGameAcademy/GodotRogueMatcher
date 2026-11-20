# #129 供给/倍率实机证据

2026-10-25，Godot4.7.2 Compatibility、Windows、RTX2070。固定种子129的真实Game场景，第4次人工供给奖励，不代表正式随机概率。

保留4张代表截图，覆盖候选/构筑、中英、大小视口及明暗。完整16组合可由 tools/mechanic_icon_preview 的 --capture-icons 重建。图标区域、正文/确认区、次数/等级与棋盘均已目视核对代表图；真人辨识速度和美学认可待作者。

- icons.log：4/4、656断言，正式次数3→0与显示纯读取。
- integration.log：56脚本319/319、8957断言、146.507秒、退出0，保留29条既有Float/Int比较警告。
- capture-gles-failed.log：最终捕获曾复现GLES初始化错误，实际有白棋盘。不能视为通过证据。
- capture.log：改用短用户目录 .godot/icon_user 后16组合导出，rule_error均为空，无GLES错误；本目录PNG取自该批。
- reopen.log：相同短用户目录第二次启动无错误。只能说明本地隔离后未复现，未证明引擎/驱动具体根因。
- asset-manifest.json：新增SVG源/尺寸/哈希。

只移除日志ANSI颜色与行尾空白，保留失败和警告。未改项目渲染配置或玩家原始数据。
