# #130 接触阴影真实渲染对比

基线70da633＋本PR明确改动，固定seed130、五种坚果45枚，同盘面/1280×720/Compatibility、NVIDIA RTX2070。仅切换各实例复制的BoardAppearance.piece_shadow.a；未改共享主题、规则、UI或背景。完整8图（含低特效）在本地忽略目录，本文保留常速普通模式两主题开关四图。

| 主题 | 关闭（原坚果无接触阴影） | 开启（本片） |
| --- | --- | --- |
| 明亮 | [关闭](light_toy_low0_shadow0.png) | [开启](light_toy_low0_shadow1.png) |
| 深色 | [关闭](dark_instrument_low0_shadow0.png) | [开启](dark_instrument_low0_shadow1.png) |

真实渲染错误日志为空，开关和两主题/低特效后规则摘要不变。图片只证明当前画面，不代替作者审美/实际成本或幽灵GPU像素专项。生成入口`tools/contact_shadow_preview`，S键同盘切换。哈希与未观察字段见captures.json，null不能解释为通过。
