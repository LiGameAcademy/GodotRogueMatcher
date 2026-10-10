import fs from 'node:fs/promises';
import path from 'node:path';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';
import {referenceUpdates} from './reference_updates.mjs';

const [input, output] = process.argv.slice(2);
if (!input || !output) throw new Error('Usage: write_observations.mjs analysis.json observations.xlsx');
const data = JSON.parse(await fs.readFile(input, 'utf8'));
const wb = Workbook.create();
const changes = [];
const names = ['观测汇总', '技能观测', '退出观察', '数据来源', '自动参考'];
const labels = {
  action_score: '行动得分', born: '实际出生', removed: '独占移除', net_space: '净释放空间',
  q_frozen: '锁定补棋数', pressure_before: '行动前压力', pressure_after: '行动后压力',
  pressure_offer: '选卡时压力', goal_actions: '达标行动数', goal_carry: '目标超额分',
  stage_completion: '阶段完成率', selection_rate: '候选选择率', unshown_offer: '未展示候选率',
  choice_score: '选卡应用得分', choice_net_space: '选卡应用净空间',
  skill_action_exposure: '安装后行动暴露', skill_trigger_rate: '能力触发率',
  paired_score: '反事实窗口净分', paired_space: '反事实窗口净空间',
  p_direct: '直接成线率', p_allclear: '全清联合率',
  interval_input: '等待输入区间', interval_busy: '演出区间', interval_choice: '选卡区间',
  interval_pause: '暂停区间', interval_inactive: '失焦区间',
};
const quality = { candidate: '候选参考', no_opportunity: '无有效机会',
  insufficient_samples: '样本不足', unknown_context: '上下文未确认',
  dataset_diagnostics_require_review: '有诊断，需审阅' };
const str = v => JSON.stringify(v);
const literal = v => typeof v === 'string' && /^[=+@-]/.test(v) ? `'${v}` : v;
function add(name, title, headers, rows) {
  const sheet = wb.worksheets.add(name);
  sheet.showGridLines = false;
  sheet.getRange('A2').values = [[title]];
  const columns = headers.length;
  const last = Math.max(5, 5 + rows.length);
  const range = sheet.getRangeByIndexes(1, 0, last - 1, columns);
  range.format.font.name = 'Microsoft YaHei';
  range.format.font.size = 10;
  range.format.rowHeight = 25;
  range.format.columnWidth = 17;
  sheet.getRange('A2').format.font.size = 14;
  sheet.getRange('A2').format.font.bold = true;
  sheet.getRange('A:A').format.columnWidth = 28;
  sheet.getRangeByIndexes(4, 0, 1, columns).values = [headers];
  sheet.getRangeByIndexes(4, 0, 1, columns).format = {
    fill: '#36594A', font: {name: 'Microsoft YaHei', bold: true, color: '#FFFFFF', size:10},
    horizontalAlignment: 'center',
  };
  if (rows.length) sheet.getRangeByIndexes(5, 0, rows.length, columns).values = rows.map(r => r.map(literal));
  sheet.freezePanes.freezeRows(5);
  sheet.freezePanes.freezeColumns(1);
  {
    const column = index => {let text=''; for(let n=index+1;n>0;n=Math.floor((n-1)/26)) text=String.fromCharCode(65+(n-1)%26)+text; return text;};
    changes.push({sheet:name,cell:'A2',old_value:null,new_value:title,result:'observation_written'});
    [headers,...rows].forEach((row,i)=>row.forEach((value,j)=>{
      if(name==='自动参考' && i>0 && i<=data.model_inputs.length && j===3) return;
      if(value !== null && value !== undefined && value !== '') changes.push({sheet:name,cell:column(j)+(i+5),
        old_value:null,new_value:literal(value),result:'observation_written',dataset_hash:data.manifest.dataset_hash});
    }));
  }
  return sheet;
}
const observations = data.metrics.filter(r => r.skill_id === null);
const summary = add('观测汇总', '试玩观测（按配置与范围分组）',
  ['指标', '阶段', '数值', '单位', '局数', '事件数', '分子', '分母', 'P50', 'P90', '簇区间95%', '质量', '组哈希', '范围', '证据索引'],
  observations.map(r => [labels[r.metric_id] ?? r.metric_id, r.stage_id ?? null,
    r.value ?? '待测', r.unit, r.n_runs, r.n_events, r.numerator, r.denominator,
    r.p50, r.p90, r.ci95 ? str(r.ci95) : '待测', quality[r.quality], r.group_hash,
    str({action_type:r.action_type, build_hash:r.build_hash, pressure_band:r.pressure_band}),
    `analysis.json:${data.metrics.indexOf(r)}:${data.manifest.dataset_hash}`]));
summary.getRange(`C6:C${Math.max(6,5+observations.length)}`).format.numberFormat = '0.00';
observations.forEach((r,i)=>{
  if(r.unit==='probability') summary.getRange(`C${i+6}`).format.numberFormat='0.0%';
});
summary.getRange('D:D').format.columnWidth = 22;
summary.getRange('K:K').format.columnWidth = 36;
summary.getRange('L:L').format.columnWidth = 23;
const skillRows = data.metrics.filter(r => r.skill_id !== null);
const skills = add('技能观测', '技能观测（不替代净收益对照）',
  ['技能ID', '等级', '指标', '数值', '单位', '局数', '事件数', '质量', '窗口H', '组哈希', '方法', '缺失原因'],
  skillRows.map(r => [r.skill_id, r.level, labels[r.metric_id] ?? r.metric_id,
    r.value ?? '待测', r.unit, r.n_runs, r.n_events, quality[r.quality], r.H,
    r.group_hash, r.method, r.missing_reasons.join('; ')]));
skills.getRange('A:A').format.columnWidth = 30;
skills.getRange('C:C').format.columnWidth = 25;
skills.getRange('E:E').format.columnWidth = 25;
skills.getRange('H:H').format.columnWidth = 23;
skills.getRange('L:L').format.columnWidth = 48;
const exits = add('退出观察', '结束与观察位置（未知停止不归因为流失）',
  ['局或会话ID', '状态', '结束分类', '界面位置', '阶段', '留档完整', '根行动完整', '距输入ms', '完整行动数', '组哈希', '原事件','对象类型','停止原因'],
  data.exits.map(r => [r.run_id??r.session_id,r.status,r.end_class,r.ui,r.stage_id,r.complete,r.root_complete,
    r.since_input_ms,r.complete_actions,r.group_hash,r.source_ref,r.subject,r.reason]));
exits.getRange('A:A').format.columnWidth = 60;
exits.getRange('J:K').format.columnWidth = 65;
exits.getRange('J:K').format.wrapText = true;
exits.getRange('M:M').format.columnWidth = 35;
exits.getRange(`A6:M${Math.max(6,5+data.exits.length)}`).format.rowHeight = 50;
const sourceRows = [
  ['数据集', data.manifest.dataset_hash, '去重后的事件内容SHA256'],
  ['退出证据集', data.manifest.evidence_hash, '事件、会话与恢复证据SHA256'],
  ['分析器', data.analyzer_version, '分位数floor(q*(n-1))；按run重采样'],
  ['参考组', data.selected_group ?? '未选择', '仅候选参考进入自动区'],
  ...Object.entries(data.groups).map(([key,value]) => ['数据组',key,str(value)]),
  ...data.manifest.files.map(f => ['原始文件',f.path,f.sha256]),
  ...data.runtime_configs.map(r=>['运行配置',r.group_hash,`analysis.json:runtime_configs:${r.source_ref}`]),
  ...data.diagnostics.map(d => ['诊断',d.reason,str(d)]),
];
const sources = add('数据来源', '数据来源与限制', ['类型','标识或路径','摘要或说明'], sourceRows);
sources.getRange('B:B').format.columnWidth = 80;
sources.getRange('C:C').format.columnWidth = 100;
sources.getRange('B:C').format.wrapText = true;
sources.getRange(`A6:C${Math.max(6,5+sourceRows.length)}`).format.rowHeight = 65;
const references = referenceUpdates(data.model_inputs,data.previous_auto??[]);
const automatic = references.rows;
changes.push(...references.changes.map((change,i)=>({...change,sheet:'自动参考',cell:`D${i+6}`,
  evidence:`analysis.json:${i};source_refs`})));
const auto = add('自动参考', '自动参考（原设计输入保持原值）',
  ['语义键','目标','范围','参考值','单位','处理结果','数据集','组哈希'], automatic);
auto.getRange('A:A').format.columnWidth = 70;
auto.getRange('B:B').format.columnWidth = 36;
auto.getRange('C:C').format.columnWidth = 65;
auto.getRange('F:H').format.columnWidth = 40;
auto.getRange('A:C').format.wrapText = true;
auto.getRange('F:H').format.wrapText = true;
auto.getRange(`A6:H${Math.max(6,5+automatic.length)}`).format.rowHeight = 80;
auto.getRange('D:D').format.numberFormat = '0.00';
wb.recalculate();
const inspection = await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!|#NULL!',
  options:{useRegex:true,maxResults:30},maxChars:2000});
await fs.writeFile(path.join(path.dirname(output),'workbook-inspection.json'), inspection.ndjson);
for (const name of names) {
  const preview = await wb.render({sheetName:name,range:name==='数据来源'?'A1:C12':'A1:J14',scale:1.5,format:'png'});
  await fs.writeFile(path.join(path.dirname(output),name+'.png'), new Uint8Array(await preview.arrayBuffer()));
}
const exported = await SpreadsheetFile.exportXlsx(wb);
await exported.save(output);
for(const change of changes) {
  change.previous_reference = change.old_value;
  change.old_value = data.previous_cells?.[change.sheet]?.[change.cell] ?? null;
  change.cell_changed = change.old_value !== change.new_value;
}
const written = new Set(changes.map(c=>JSON.stringify([c.sheet,c.cell])));
for(const [sheet,cells] of Object.entries(data.previous_cells??{})) for(const [cell,oldValue] of Object.entries(cells)) {
  if(oldValue!==null && !written.has(JSON.stringify([sheet,cell]))) changes.push({sheet,cell,old_value:oldValue,new_value:null,
    result:'old_observation_cell_cleared',cell_changed:oldValue!==null});
}
const keys = [...new Set(changes.flatMap(r=>Object.keys(r)))];
const escape = v => '"'+String(literal(v)??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(path.dirname(output),'changes.csv'),'\ufeff'+
  [keys.join(','), ...changes.map(r=>keys.map(k=>escape(r[k])).join(','))].join('\n')+'\n');
console.log(`OBSERVATION_SHEETS=${names.length} REFERENCE_ROWS=${automatic.length} CHANGES=${changes.length}`);
