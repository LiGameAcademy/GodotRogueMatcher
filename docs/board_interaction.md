# Board interaction in the 0.0.3 development build

These controls describe the development branch, not the currently published Web preview.

- Hover a piece for a light outline. Click to select it; selection corners remain visible.
- Click the selected piece again to cancel, or another piece to switch selection.
- Reachable empty cells receive a subtle border. Hover one to preview the same legal path used by movement validation. Previewing never spends an action or advances gameplay randomness.
- Click a reachable empty cell to move. An unreachable destination briefly changes color, plays the existing rejection cue and clears selection. Clicking an empty cell without a selection does nothing.
- After committing, the path and destination remain visible; traversed segments fade. Local body deformation follows movement direction and recovers on landing. Long paths share one movement clock rather than waiting once per cell.
- Fast playback shortens presentation. Low effects keeps selection, paths and destinations readable while disabling body deformation and selection breathing.
- Removals share the existing parallel shrink/fade. Blast and sweep effects and sounds explain their cause; pieces do not receive separate knockback animations.

Animation strength and timing remain trial settings pending consolidated O4 acceptance. Presentation consumes committed results and does not change matching, scoring, paths or random streams.

## 中文

以上为0.0.3开发分支行为，尚不代表公开Web版本已经更新。

悬停棋子显示轻描边，点击后保持选中角标；再次点击自己取消，点击其他棋子切换。可达空格弱提示，悬停目标格预览合法路径。提交后路径保留并逐段淡出；不可达点击短促变色、沿用拒绝音并取消选择，无选择时点击空格不处理。

棋子沿移动方向轻微形变，落定恢复；长路径使用一个总时钟。快速模式压缩表现，低特效保留必要提示并取消形变与呼吸。消除沿用同批并行缩退和现有原因特效，不增加击飞或逐枚等待。具体强度与时长仍待完整O4集中体验接受。
