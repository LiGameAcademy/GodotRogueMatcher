# 坚果主题图元

2026-10-24追加：selection_corner_top_left已由四个TextureRect旋转复用，sweep_arrow_right已按横/竖双向复用；AtlasTexture去留白，PNG未改。见[实机标记与参数](../../../art/samples/nut_markers_godot_v01/README.md)。

2026-10-24接入进展：五种身体与eyes_idle/mouth_smile已由NutVisual共用，棋盘/预告统一绘制；设置/暂停图标已绑定HUD。backgrounds/garden_background.png为补制庭院背景候选。见[实装截图及剩余图元](../../../art/samples/nut_gameplay_godot_v01/README.md)。下文“未绑定”是此前入库阶段的历史状态。

2026-10-24新增UI切图接入候选：`ui/icon_settings.png`、`icon_pause.png`、`icon_history.png`、`icon_chevron_down.png`（后者三张同在ui目录）为白色RGB＋alpha单色符号，必须由主题/控件着色；`ui/icon_ability_explosion.png`、`ui/icon_ability_sweep.png`为彩色构筑机制图标。原切片、阈值处理、尺寸、哈希及对照见`art/samples/ui_icons_v01/README.md`，副本内容一致，未绑定场景。机制图标不替换`board/sweep_arrow_right.png`棋盘能力图元。

文件命名遵守教程工作区[资产命名规范](../../../art/资产命名规范.md)。当前文件名沿用，后续按固定角色/姿态词表新增；源图版本放在art样稿目录，运行路径保持稳定。设计编号和验收状态在登记里维护，不追加final或new。

2026-10-21。当前为已入库的接入试用素材，尚未绑定场景或替换旧主题。

| 资源 | 用途与复用 | 来源 |
| --- | --- | --- |
| `ui/selection_corner_top_left.png` | 左上角标；其余三角通过90/180/270度旋转复用 | `art/samples/selection_corner_v01/` |
| `board/sweep_arrow_right.png` | 朝右扫线箭头；左/上/下通过旋转复用，成对放于棋子外侧 | `art/samples/sweep_arrow_v01/` |
| `pieces/peanut_body.png` | 开壳红皮花生身体，无五官 | `art/samples/piece_bodies_v01/` |
| `pieces/cashew_body.png` | 奶油黄腰果身体，无五官 | 同上 |
| `pieces/almond_body.png` | 肉桂色杏仁身体，无五官 | 同上 |
| `pieces/walnut_body.png` | 灰可可核桃身体，无五官 | 同上 |
| `pieces/pistachio_body.png` | 米白壳、绿色果仁开心果身体，无五官 | 同上 |
| `faces/eyes_idle.png` | E0双眼与短眉，首批共用待机眼部候选 | `art/samples/idle_layers_v01/` |
| `faces/mouth_smile.png` | M0闭嘴小笑，与眼部独立定位 | 同上 |
| `faces/eyes_focus.png` | E2蓄劲/专注眼部候选 | `art/samples/emotion_layers_v01/` |
| `faces/mouth_purse.png` | M1抿嘴候选，与E2配对 | 同上 |
| `faces/eyes_happy.png` | E3开心弯眼候选 | 同上 |
| `faces/mouth_happy.png` | M2短开口笑候选，与E3配对 | 同上 |
| `faces/eyes_surprise.png` | E5惊讶睁眼，2026-10-23新增候选 | 同上 |
| `faces/mouth_round.png` | M4小圆嘴，与E5配对 | 同上 |
| `faces/eyes_attentive.png` | E1期待/注意眼部候选，复用M0 | `art/samples/expression_completion_v01/` |
| `faces/eyes_smug.png` | E4得意半眯眼候选 | 同上 |
| `faces/mouth_smirk.png` | M3歪嘴笑候选，与E4配对 | 同上 |
| `faces/eyes_sad.png` | E6受挫眼部候选 | 同上 |
| `faces/mouth_flat.png` | M5扁嘴轻垂候选，与E6配对 | 同上 |
| `faces/eyes_blink_closed.png` | EB闭眼关键姿态候选，不是完整动画 | 同上 |

剩余基础表情的统一坐标、图层比例、留白校准与文件检查见`art/samples/expression_completion_v01/README.md`。共有8种眼姿态、6种嘴形，以指定配方组合，不随机全排列。新增姿态尚待作者评审。

2026-10-23作者已暂时定稿蓄劲/开心两组；上表对应“候选”是原制作状态。惊讶两张仍待评审，来源与文件检查见`art/samples/emotion_layers_v01/README.md`。

作者已确认v02统一布局。新增两种表情仍待评审；图层参考点校准、实际PNG组合证据见`art/samples/emotion_layers_v01/README.md`。这些是静态姿态，不是序列帧或已验收眨眼动画。

眼嘴均1254×1254 RGBA，保留生成原图，不按身体轮廓裁切。HTML棋盘组合、定位百分比与48/64/96像素对照见`art/samples/idle_layers_v01/README.md`；48像素嘴线偏弱待评审。它们尚未被Godot场景引用，角色专属待机差异尚未制作。

以上由本对话内置image_gen生成；完整提示词与原始图片保存在教程工作区art对应目录。本目录保存接入候选，当前没有场景引用。颜色来自当前认可的概念图；独立资源仍需作者查看、小尺寸和实际棋盘验证。

五种身体均1254×1254 RGBA透明PNG，工程副本与源图哈希一致。身体占幅/中心尚未统一，部分有极淡alpha残留；不能直接使用统一控件尺寸当作最终显示比例。后续眼睛、嘴巴分层叠加，爆破描光仅取身体遮罩。文件边界与目视差异见`art/samples/piece_bodies_v01/README.md`。

图片为高分辨率RGBA并带真实透明通道。角标原图存在极低透明残留；两图的外侧透明留白均应按实际显示区域设置，不假定画布边缘等于可见形状边缘。未做精确数学对称、颜色或低透明像素清理；当前不能称最终生产验收通过。

导入时保持alpha；UI小尺寸优先检查线性过滤、mipmap与缩放后的边缘，不在本文硬定所有显示尺寸。当前未写入.import配置，由编辑器正常生成导入元数据。图片只读共享，旋转/透明度/缩放优先作用于节点；运行Shader的实例参数与可变材质隔离在接入阶段验证。

角标四个TextureRect不拦截输入，旋转中心与锚点一致；箭头始终依棋盘水平/垂直轴放置，不跟随坚果斜放角度。辉光与脉冲不再叠加重复的大面积亮边。

## #129 首批机制图标接入（2026-10-24）

既有爆破与扫线图元现用于7张正式技能卡的三选一、技能池和构筑栏。列扫使用独立节点旋转90度，构筑以登场/补给/范围小字区分同族技能；其余卡保留文字回退。此前未绑定/待制作表述为制作时状态；本片不意味着全部机制图标或作者美学验收完成。清单与证据见 `docs/quality/issue129_mechanic_icons.md`。

## #129 供给与倍率图元（2026-10-25）

新增三个原创32×32 SVG：icon_ability_refill_less、icon_ability_refill_more、icon_ability_multiplier。前两者共用补棋托盘，以−/+区分，倍率用×；源文件就是可编辑素材，无新外部授权依赖。用于留白一手、加速播种、计分倍率，复用三选一/技能池/构筑显示清单；次数/等级沿用原状态，未改数值或规则。详见 docs/quality/issue129_supply_multiplier_icons.md；其余未登记机制仍文字回退。

## #129 常驻染色图元（2026-10-25）

新增原创32×32 SVG icon_ability_dye，源文件即可编辑。水滴轮廓沿现有暖白/梅紫/青绿/浅紫色系，描边兼顾明暗底；内部双色只是染色机制示意，不承诺实际目标色。用于染色接续、染色扩散、再续一线，构筑以接续/扩散/再续与等级区分。同族其余即时/收益/复合技能暂不绑定。来源、成本和证据见 docs/quality/issue129_dye_icons.md。

## #129 常驻引信图元（2026-10-25）

新增原创32×32 SVG icon_ability_fuse，以引信绳和火花提示家族，源文件即可编辑。用于消除布雷、引信传递、传递接力；构筑用布雷/传递/接力与真实等级区分。图元不表示核心出生、立即引爆、实际传播结果或引信剩余数；引信赋能/双份引信/即时引爆等仍回退。沿用只读纹理、独立节点和现有Theme，来源/成本及证据见 docs/quality/issue129_fuse_icons.md。

## #129 五连额外分图元（2026-10-25）

新增原创32×32 SVG icon_ability_match_bonus，以金色圆角框/加号表示五连额外分，与浅紫八角框/乘号的计分倍率分开。用于连珠补分、五枚正好、长连收获；构筑用补分/正好/长连与真实等级区分。正好5枚、至少6枚及倍率限制仍由正文说明，符号不承诺无条件收益。其他收益卡暂不绑定，来源/成本及证据见 docs/quality/issue129_match_bonus_icons.md。

## #129 爆破收益图标接入（2026-10-25）

复用现有 icon_ability_explosion.png，新增爆破补分、爆破节拍、爆后留白三项显示绑定；构筑用补分/节拍/留白与真实等级区分，五连补分仍保留独立加号。没有新增或改动生产图像，源哈希与既有批次一致；触发条件由正文保留，图元不表示即时引爆或已有临时补棋次数。来源/复用成本与证据见 docs/quality/issue129_blast_payoff_icons.md。

## #129 主动机制图标与轮廓（2026-10-25）

主动爆破复用现有爆破PNG；主动扫线新增原创64×64可编辑SVG icon_ability_manual_sweep，金色双轴箭头配深梅紫边，表示横/竖共用主动权限，不承诺一次扫两个方向。两卡构筑用主动/Manual及真实等级、剩余次数，耗尽仍保留。棋盘爆破手与引信轮廓通过原生shader增强为连续/分段金色带及深色细边，不产生逐状态整图；普通/低特效均保留静态身份。来源、维护量、同盘面前后图与回归见 docs/quality/issue129_manual_icons_outlines.md。
