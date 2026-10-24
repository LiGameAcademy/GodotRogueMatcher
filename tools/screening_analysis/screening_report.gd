class_name ScreeningReport
extends RefCounted

var runs: Array[Dictionary] = []
var diagnostics: Array[Dictionary] = []
var duplicate_files: int = 0
var _seen: Dictionary[String, String] = {}
var _conflicts: Dictionary[String, bool] = {}
var error: String = ""

func add(path: String) -> void:
	var reader: ScreeningRecordReader = ScreeningRecordReader.new()
	var row: Dictionary = reader.read(path)
	if row.is_empty():
		diagnostics.append({"record": path, "severity": "warning" if reader.error == "not_screening_record" else "error", "reason": reader.error})
		return
	var id: String = row.run_id
	var fingerprint: String = row.sha256 + ":" + str(row.sidecar_sha256)
	if _conflicts.has(id):
		diagnostics.append({"record": path, "severity": "error", "reason": "conflicting_duplicate_run"})
		return
	if _seen.has(id):
		if _seen[id] == fingerprint:
			duplicate_files += 1
			return
		_conflicts[id] = true
		runs = runs.filter(func(run: Dictionary) -> bool: return run.run_id != id)
		diagnostics.append({"record": path, "severity": "error", "reason": "conflicting_duplicate_run"})
		return
	_seen[id] = fingerprint
	runs.append(row)

func build(document: Dictionary = {}) -> Dictionary:
	var rows: Array[Dictionary] = []
	for run: Dictionary in runs:
		var copy: Dictionary = run.duplicate(true)
		copy.human = ScreeningRecordReader.blank_human()
		rows.append(copy)
	var annotations: ScreeningAnnotations = ScreeningAnnotations.new()
	var decisions: Array[Dictionary] = annotations.apply(document, rows)
	var issues: Array[Dictionary] = diagnostics.duplicate(true)
	for message: String in annotations.errors: issues.append({"record": null, "severity": "error", "reason": message})
	var results: Array[Dictionary] = []
	for key: String in ScreeningDeck.CONFIGS:
		var config: String = "screening-%s-v1" % key
		var values: Array[Dictionary] = rows.filter(func(r: Dictionary) -> bool: return r.config_id == config)
		var manual: Array[Dictionary] = decisions.filter(func(d: Dictionary) -> bool: return d.config_id == config)
		results.append({"config_id": config, "valid_records": values.size(), "automated_records": values.filter(func(r: Dictionary) -> bool: return r.source_kind == "automated").size(), "annotated_human_trials": values.filter(func(r: Dictionary) -> bool: return r.human.participant != null).size(), "screening_decision": manual[0] if not manual.is_empty() else null, "human_comprehension": null, "natural_encounter_rate": null})
	return {"schema": "screening-report-v1", "runs": rows, "configurations": results, "fixed_task_accuracy": ScreeningAnnotations.accuracy(rows), "duplicate_files": duplicate_files, "diagnostics": issues, "observation_template": ScreeningAnnotations.template(rows)}

func write(directory: String, document: Dictionary = {}) -> bool:
	error = ""
	var names: Array[String] = ["screening-report.json", "screening-report.md", "observations-template.json"]
	for name: String in names:
		if FileAccess.file_exists(directory.path_join(name)):
			error = "output_exists:" + name
			return false
	var code: Error = DirAccess.make_dir_recursive_absolute(directory)
	if code != OK:
		error = error_string(code)
		return false
	var report: Dictionary = build(document)
	var contents: Array[String] = [JSON.stringify(report, "  "), markdown(report), JSON.stringify(report.observation_template, "  ")]
	for index: int in range(names.size()):
		var file: FileAccess = FileAccess.open(directory.path_join(names[index]), FileAccess.WRITE)
		if file == null:
			error = error_string(FileAccess.get_open_error())
			return false
		file.store_string(contents[index] + "\n")
		file.flush()
		code = file.get_error()
		file.close()
		if code != OK:
			error = error_string(code)
			return false
	return true

static func markdown(report: Dictionary) -> String:
	var text: String = "# #119 试玩记录汇总\n\n自动统计与人工观察分开；空白为未观察。3/4仅为排查指标，不自动决定保留。作者确认字段是人工录入声明。\n\n| 配置 | 有效记录 | 自动样本 | 人工标注条数 | 人工筛选结论 |\n| --- | --- | --- | --- | --- |\n"
	for row: Dictionary in report.configurations:
		var decision: String = "未观察"
		if row.screening_decision != null: decision = str(row.screening_decision.decision) + ("（录入为作者已确认）" if row.screening_decision.author_confirmed else "（待作者确认）")
		text += "| %s | %d | %d | %d | %s |\n" % [_cell(row.config_id), row.valid_records, row.automated_records, row.annotated_human_trials, _cell(decision)]
	text += "\n## 单条记录\n\n| run_id | 配置/题 | 来源 | 状态/窗口 | 行动 | 分数 | 净空位变化 |\n| --- | --- | --- | --- | --- | --- | --- |\n"
	for row: Dictionary in report.runs:
		text += "| %s | %s/%s | %s | %s/%s | %d | %d | %d |\n" % [_cell(row.run_id), _cell(row.config_id), _cell(row.task), _cell(row.source_kind), _cell(row.reason), "完整" if row.window_complete == true else "不完整或未验证", row.actions, row.score, row.metrics.net_empty_cells]
	text += "\n## 固定题人工核对\n\n"
	if report.fixed_task_accuracy.is_empty(): text += "未观察。\n"
	for row: Dictionary in report.fixed_task_accuracy:
		text += "- %s / %s / %s / %s：预测已观察%d题，正确%s；一次说明后3/4=%s，重复题=%s。版本%s / 指纹%s / seed=%s。\n" % [_cell(row.participant), _cell(row.role), _cell(row.round), _cell(row.config_id), row.prediction_observed, _cell(row.prediction_correct), _cell(row.once_explained_three_of_four), _cell(row.duplicate_task), _cell(row.build), _cell(row.config_hash), _cell(row.seed)]
	text += "\n## 人工观察原文\n\n"
	var observed: bool = false
	for row: Dictionary in report.runs:
		if row.human.participant == null: continue
		observed = true
		text += "- %s / %s（%s，%s）：说明次数%s，预测正确%s，主动布局%s，愿意再选%s；用途：%s；材料干扰：%s；备注：%s。\n" % [_cell(row.run_id), _cell(row.human.participant), _cell(row.human.role), _cell(row.human.round), _cell(row.human.explanation_count), _cell(row.human.prediction_correct), _cell(row.human.planned_layout), _cell(row.human.willing_again), _cell(row.human.use_case), _cell(row.human.interference), _cell(row.human.notes)]
	if not observed: text += "未观察。\n"
	text += "\n## 人工结论与证据\n\n"
	var decided: bool = false
	for row: Dictionary in report.configurations:
		if row.screening_decision == null: continue
		decided = true
		var decision: Dictionary = row.screening_decision
		text += "- %s / %s / %s：%s，作者确认录入值%s。理由：%s。引用run_id：%s。\n" % [_cell(row.config_id), _cell(decision.build), _cell(decision.config_hash), _cell(decision.decision), _cell(decision.author_confirmed), _cell(decision.reason), _cell(decision.evidence_run_ids)]
	if not decided: text += "未观察。\n"
	text += "\n## 诊断\n\n完全相同记录副本去重：%d。冲突run_id隔离；错误不会改写成零分或真人未触发。\n" % report.duplicate_files
	for row: Dictionary in report.diagnostics: text += "- %s：%s（%s）\n" % [_cell(row.severity), _cell(row.reason), _cell(row.record)]
	return text

static func _cell(value: Variant) -> String:
	if value == null: return "未观察"
	return str(value).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("|", "&#124;").replace("[", "&#91;").replace("\n", " ").replace("\r", " ")
