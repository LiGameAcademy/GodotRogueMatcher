# 六卡描述批证据

源码冻结：`2cc4c8463e36e317f2ee1269b3635128bba7746f`；目标基线：`7d78fd8fa26624b6ad7f81fe5c9447a60c856e54`（#211）。后续提交仅加入本目录及quality记录，不改变已受测源文件。逐文件物理SHA256与行数见source-manifest.json。

Godot 4.7.2 `ed1daf0bf` / GUT 9.6；Windows；真实GPU为NVIDIA GeForce RTX 2070，Compatibility/OpenGL 3.3。CPU、内存、缩放、刷新率及弱机未采集/null。隔离APPDATA/LOCALAPPDATA，未改作者窗口或偏好；测试不是性能测量或真人接受。

| 检查 | 实值 / 证据 |
| --- | --- |
| 最终相关回归 | 6脚本34/34、4383断言、exit0；regression.log；真实规则/配置/六随机流不变、双语卡面/构筑、两尺寸/少张/选中失效、原生鼠标确认、默认主题Popup、Game闭环与v46回放拒绝 |
| 最终GPU | 3/3、283断言、exit0；gpu.log；同一2cc源码重采8图并逐张目检，修复后英文Action/tooltip均为Target no longer valid |
| 源文件边界 | 9个相关自有GDScript均≤500物理行；source-manifest.json登记准确行数，差异空白检查通过 |
| 独立代码复审 | d329d3f5（后续8fa仅EOF清理）及8fa→2cc增量均无剩余阻断；本地只读复审，不是GitHub批准或远端CI |
| 真人 | 作者、非设计者、#131整体验收均null |

两套日志均可能含沙箱根证书读取限制，断言通过不等于零ERROR日志；最终退出对象/资源保留是否出现按validation.json原日志扫描记录，不把历史问题称已修。未执行整库、机器人批测或发行导出。

## 历史失败及纠正

两份带失败断言的长日志提供去ANSI控制码/行尾空白的可读版，同时保留字节完全一致的原始`.log.gz`；原始、压缩与可读版SHA256见validation.json，不删失败内容或改测试数字。

- development-display-contract-failures.log：1a03cb1基础上的开发中树，旧显示契约集21项17过4失败。原断言要求无标记人工回退、旧补棋逐字预览及正文消耗词、旧D06预览，均由本批替换成等价或更强语义断言；不删除回放/规则门禁。
- pre-import-failure.log：合入#211后未刷新全局类缓存的首次组合试跑，新增OfferRarityStep/SkillOfferTraits不可见，23项失败。随后editor导入解决环境准备问题，没有修改生产规则迎合这些失败；该批不计通过。
- before-diagnostic-assertion-update.log：8fa源码树相关集33/34，唯一失败是缺Effect负例期待旧“effect missing”，#211已由配置验证先返回“skill has no acquisition effect”。更新诊断断言并保留Manual rule验证；最终34/34另见regression.log。
- before-card-reason-fix/：8fa的GPU技术267断言通过，但随后八图目检发现英文失效文案露出中文，因此不能称双语验收通过。保留两张英文失败截图及该批gpu.log。2cc只在专属翻译表补齐此卡面消息，Action/tooltip原tr消费者均有独立英文断言，未换fixture绕过问题。
- 早期完整正文还曾溢出360px卡面、扩大高度后超出小视口。已修本批引入的排版回归，最终采用视口/主题边距约束三卡宽、高度随正文；不是旧版历史缺陷。开发中间每次临时图未全部封存，未保存批的完整提交身份未知，不推算为某个已提交版本成绩。

## 最终图片

最后GPU批须在同一2cc冻结源码上重采全部8张，不把旧图按新head命名。文件名分别为中英、1024/1280宽、group0/group1；实际视口为1024×640和1280×720。group0为D01/D02/D03，group1为D06/D05/D04。每组使用显示fixture及明确冻结数值，不是自然抽卡/正式掉率样本；短句仅显示样例，不写入正式Resource。

D01预览0→0.2贡献、D02名义1→3行、D04+25读取对应资源；D03/D05净补棋与余次、D05冻结颜色权重、D06执行后随机目标提示分别展示。失效状态为“原定目标已经失效”，只展示既有失效表达，不制造正式规则变化。8图逐张核对全文、两生命周期分行、短句和操作区；原生鼠标确认由同一GPU专项验证，不能把截图本身叫点击测试。

复现命令见[quality记录](../../quality/issue129_rule_descriptions.md)。卡池当前为配置定义语境；运行等级单次接入与#131真人/设备出口保留，不由本批截图代替。
