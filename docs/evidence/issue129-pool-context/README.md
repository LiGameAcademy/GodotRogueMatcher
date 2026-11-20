# 技能池语境批证据

冻结源码`1201816b4f11ce465b3e0cdca92eeb2a73e35b9e`，基线`e3e3f978ad0ae9f0555756475c7392862c594036`；后续只提交本目录和quality文档，源码文件SHA256/行数见source-manifest.json。

| 证据 | 实际结果与身份 |
| --- | --- |
| related-regression.log | 冻结源码业务/测试内容，4脚本14/14、3994断言、exit0；新覆盖/语境＋旧卡面/构筑 |
| gpu.log | 1201816，真实GUI 3/3、506断言、exit0，8图逐张目检；当前/定义/拟取得、最大级、临时余次、两语全池、Scroll元信息可达和返回可见 |
| early-pool-regression.log | e3基线上的本批开发中树，4脚本24/24、1443断言；池/描述原集及最初覆盖/语境。没有伪记受测commit，未计为新冻结树全量 |
| coverage.json | 52正式Resource，12卡生成、40人工回退；记录真实Effect class/script/parameters、声明等级、两语正文与定位诊断。无限升级旧路径只审一级配置 |
| initial-fixture-failure.log / .gz | 最初测试夹具初始化mode错误导致安装失败，3/4、720/722断言；改用合法fixture_dye并加rule_error断言，不修改生产规则 |

日志可读版只去ANSI控制码与行尾空白；失败批的原始字节保留在.gz中。日志、图片和源码哈希、环境诊断见validation.json。Godot4.7.2 ed1daf0bf / GUT9.6，Windows，RTX2070 Compatibility/OpenGL3.3，隔离APPDATA/LOCALAPPDATA；没有性能测量、弱机或真人接受结论。最终root certificate错误属已有沙箱限制，未隐藏。

图片文件名含语言/宽度/卡ID：line_column_span展示未持有的配置定义，composite_refill_color展示已持有D05与真实剩余；同一52卡池按既有排序滚动定位，未删除其他卡或伪造“52/52”。1024×640与1280×720，普通明亮主题。英语长卡底部可能位于Scroll下一段，专项另滚动验证整个语境/前置/资格标签可达；图片不是全长拼接图或所有52卡同时可见的证明。

复现（先editor导入，新工作树需初始化已锁定CoreSystem子模块）：

```powershell
$env:APPDATA = Join-Path $env:TEMP 'o4-pool-review'
$env:LOCALAPPDATA = $env:APPDATA
$engine = 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/rules/test_skill_description_coverage.gd,res://tests/integration/test_skill_pool_rule_context.gd -gexit
$env:O4_POOL_CAPTURE = '1'
& $engine --path . -s addons/gut/gut_cmdln.gd -gopacity=0 -gtest=res://tests/integration/test_skill_pool_rule_context.gd -gexit
```

作者读感、非设计者、#131整体体验均null。本批按B交付，保留#129 OPEN及40项回退；不以自动合并代表整体验收或发行。
