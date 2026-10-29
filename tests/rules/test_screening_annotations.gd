extends GutTest

const CURRENT: Script = preload("res://tests/support/screening_current_records.gd")
var _record_path: String

func before_all() -> void:
	_record_path = CURRENT.write("user://screening_annotation_current/%s" % str(Time.get_ticks_usec()), "ui-t-overlap")
	assert_false(_record_path.is_empty())
## Synthetic observation fixtures only; never evidence of actual participants.
func _runs() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for task: String in ScreeningDeck.TASKS.slice(1):
		rows.append({"run_id": "synthetic-" + task, "task": task, "config_id": "screening-t-v1", "config_hash": "synthetic-hash", "build": "synthetic-build", "seed": "119", "window_complete": true, "source_kind": "human_unobserved", "human": ScreeningRecordReader.blank_human()})
	return rows

func _document(runs: Array[Dictionary], count: int = 4) -> Dictionary:
	var doc: Dictionary = ScreeningAnnotations.template(runs)
	for index: int in range(count):
		doc.observations[index].participant = "synthetic-P1"
		doc.observations[index].role = "new_player"
		doc.observations[index].round = "initial"
		doc.observations[index].explanation_count = 1
		doc.observations[index].prediction_correct = index != 3
	return doc

func test_blank_template_preserves_null_for_all_unobserved_values() -> void:
	var runs: Array[Dictionary] = _runs()
	var document: Dictionary = ScreeningAnnotations.template(runs)
	var parser: ScreeningAnnotations = ScreeningAnnotations.new()
	assert_true(parser.apply(document, runs).is_empty())
	assert_true(parser.errors.is_empty())
	assert_true(ScreeningAnnotations.accuracy(runs).is_empty())
	for row: Dictionary in runs:
		for value: Variant in row.human.values(): assert_null(value)
	for row: Dictionary in document.decisions:
		assert_null(row.decision)
		assert_null(row.author_confirmed)
		assert_null(row.evidence_run_ids)

func test_partial_results_and_explicit_false_are_not_filled_or_promoted() -> void:
	var runs: Array[Dictionary] = _runs()
	var doc: Dictionary = _document(runs, 2)
	doc.observations[0].willing_again = false
	var parser: ScreeningAnnotations = ScreeningAnnotations.new()
	assert_true(parser.apply(doc, runs).is_empty())
	assert_true(parser.errors.is_empty())
	assert_false(runs[0].human.willing_again)
	assert_null(runs[2].human.prediction_correct)
	var groups: Array[Dictionary] = ScreeningAnnotations.accuracy(runs)
	assert_eq(groups[0].prediction_observed, 2)
	assert_null(groups[0].once_explained_three_of_four)

func test_four_unique_once_explained_tasks_yield_only_a_diagnostic_three_of_four() -> void:
	var runs: Array[Dictionary] = _runs()
	var parser: ScreeningAnnotations = ScreeningAnnotations.new()
	var decisions: Array[Dictionary] = parser.apply(_document(runs), runs)
	assert_true(decisions.is_empty())
	var groups: Array[Dictionary] = ScreeningAnnotations.accuracy(runs)
	assert_eq(groups[0].prediction_correct, 3)
	assert_true(groups[0].once_explained_three_of_four)
	assert_eq(groups[0].role, "new_player")

func test_repeated_tasks_unknown_explanations_and_retest_or_version_changes_never_pool() -> void:
	for variation: int in range(6):
		var runs: Array[Dictionary] = _runs()
		var doc: Dictionary = _document(runs)
		if variation == 0:
			var extra: Dictionary = runs[0].duplicate(true)
			extra.run_id = "synthetic-duplicate-task"
			runs.append(extra)
			var note: Dictionary = doc.observations[0].duplicate(true)
			note.run_id = extra.run_id
			doc.observations.append(note)
		if variation == 1: doc.observations[0].explanation_count = null
		if variation == 2: doc.observations[0].round = "retest"
		if variation == 3: runs[0].config_hash = "different"
		if variation == 4: doc.observations[0].role = "author"
		if variation == 5: runs[0].seed = "different"
		var parser: ScreeningAnnotations = ScreeningAnnotations.new()
		parser.apply(doc, runs)
		assert_true(parser.errors.is_empty())
		for group: Dictionary in ScreeningAnnotations.accuracy(runs): assert_null(group.once_explained_three_of_four)

func test_invalid_types_unknown_ids_and_duplicate_observations_are_rejected() -> void:
	for value: Variant in ["false", 0, [], {}]:
		var runs: Array[Dictionary] = _runs()
		var doc: Dictionary = _document(runs, 1)
		doc.observations[0].prediction_correct = value
		var parser: ScreeningAnnotations = ScreeningAnnotations.new()
		parser.apply(doc, runs)
		assert_eq(parser.errors.size(), 1)
		assert_null(runs[0].human.participant)
	var runs: Array[Dictionary] = _runs()
	var doc: Dictionary = _document(runs)
	doc.observations.append(doc.observations[0].duplicate(true))
	doc.observations.append({"run_id": "unknown"})
	var parser: ScreeningAnnotations = ScreeningAnnotations.new()
	parser.apply(doc, runs)
	assert_eq(parser.errors.size(), 2)

func test_automation_cannot_be_relabelled_as_observed_human() -> void:
	var runs: Array[Dictionary] = _runs()
	runs[0].source_kind = "automated"
	assert_eq(ScreeningAnnotations.template(runs).observations.size(), 3)
	var note: Dictionary = ScreeningRecordReader.blank_human()
	note.merge({"run_id": runs[0].run_id, "participant": "P", "role": "new_player", "round": "initial"}, true)
	var doc: Dictionary = {"schema": "screening-observations-v1", "observations": [note], "decisions": []}
	var parser: ScreeningAnnotations = ScreeningAnnotations.new()
	parser.apply(doc, runs)
	assert_eq(parser.errors.size(), 1)
	assert_null(runs[0].human.participant)

func test_manual_decision_requires_scope_reason_confirmation_and_existing_evidence() -> void:
	var runs: Array[Dictionary] = _runs()
	var doc: Dictionary = _document(runs)
	var decision: Dictionary = {"config_id": "screening-t-v1", "config_hash": "synthetic-hash", "build": "synthetic-build", "decision": "adjust", "reason": "synthetic fixture", "author_confirmed": false, "evidence_run_ids": [runs[0].run_id]}
	doc.decisions = [decision]
	var parser: ScreeningAnnotations = ScreeningAnnotations.new()
	var values: Array[Dictionary] = parser.apply(doc, runs)
	assert_eq(values.size(), 1)
	assert_false(values[0].author_confirmed)
	doc.decisions[0].evidence_run_ids = ["unknown"]
	assert_true(parser.apply(doc, runs).is_empty())
	assert_eq(parser.errors.size(), 1)
	doc.decisions[0].evidence_run_ids = [runs[0].run_id]
	doc.decisions[0].config_hash = "different"
	assert_true(parser.apply(doc, runs).is_empty())
	assert_eq(parser.errors.size(), 1)

func test_report_build_does_not_mutate_original_or_invent_people_from_notes() -> void:
	var report: ScreeningReport = ScreeningReport.new()
	report.add(_record_path)
	var raw: String = JSON.stringify(report.runs)
	var doc: Dictionary = ScreeningAnnotations.template(report.runs)
	doc.observations[0].participant = "synthetic-P"
	doc.observations[0].role = "author"
	doc.observations[0].round = "initial"
	doc.observations[0].notes = "synthetic note"
	var annotated: Dictionary = report.build(doc)
	assert_eq(annotated.runs[0].human.participant, "synthetic-P")
	assert_null(annotated.runs[0].human.prediction_correct)
	var empty: Dictionary = report.build()
	assert_null(empty.runs[0].human.participant)
	assert_eq(JSON.stringify(report.runs), raw)

func test_conflicting_duplicate_human_rows_and_decisions_are_quarantined() -> void:
	var runs: Array[Dictionary] = _runs()
	var doc: Dictionary = _document(runs)
	var duplicate: Dictionary = doc.observations[0].duplicate(true)
	duplicate.prediction_correct = false
	doc.observations.append(duplicate)
	var parser: ScreeningAnnotations = ScreeningAnnotations.new()
	parser.apply(doc, runs)
	assert_null(runs[0].human.participant)
	assert_false(parser.errors.is_empty())
	for group: Dictionary in ScreeningAnnotations.accuracy(runs): assert_null(group.once_explained_three_of_four)
	var decision: Dictionary = {"config_id": "screening-t-v1", "config_hash": "synthetic-hash", "build": "synthetic-build", "decision": "adjust", "reason": "synthetic", "author_confirmed": false, "evidence_run_ids": [runs[0].run_id]}
	doc.observations = _document(runs).observations
	doc.decisions = [decision, decision.duplicate(true)]
	assert_true(parser.apply(doc, runs).is_empty())
	assert_eq(parser.errors.size(), 1)
	parser.apply({}, runs)
	for run: Dictionary in runs: assert_null(run.human.participant)

func test_decisions_need_observed_evidence_except_explicit_insufficient() -> void:
	var runs: Array[Dictionary] = _runs()
	var doc: Dictionary = _document(runs)
	var decision: Dictionary = {"config_id": "screening-t-v1", "config_hash": "synthetic-hash", "build": "synthetic-build", "decision": "retain", "reason": "synthetic", "author_confirmed": true, "evidence_run_ids": []}
	doc.decisions = [decision]
	var parser: ScreeningAnnotations = ScreeningAnnotations.new()
	assert_true(parser.apply(doc, runs).is_empty())
	assert_eq(parser.errors.size(), 1)
	doc.observations = []
	doc.decisions[0].evidence_run_ids = [runs[0].run_id]
	assert_true(parser.apply(doc, runs).is_empty())
	assert_eq(parser.errors.size(), 1)
	doc.decisions[0].decision = "insufficient"
	doc.decisions[0].evidence_run_ids = []
	assert_eq(parser.apply(doc, runs).size(), 1)
	assert_true(parser.errors.is_empty())

func test_markdown_includes_observation_reason_and_evidence_as_escaped_text() -> void:
	var report: ScreeningReport = ScreeningReport.new()
	report.add(_record_path)
	var run: Dictionary = report.runs[0]
	var doc: Dictionary = ScreeningAnnotations.template(report.runs)
	doc.observations[0].participant = "synthetic-P"
	doc.observations[0].role = "author"
	doc.observations[0].round = "initial"
	doc.observations[0].prediction_correct = false
	doc.observations[0].willing_again = false
	doc.observations[0].notes = "<script>|[x]\nsynthetic"
	doc.decisions = [{"config_id": run.config_id, "config_hash": run.config_hash, "build": run.build, "decision": "adjust", "reason": "synthetic reason", "author_confirmed": false, "evidence_run_ids": [run.run_id]}]
	var result: Dictionary = report.build(doc)
	var text: String = ScreeningReport.markdown(result)
	assert_false(text.contains("<script>"))
	assert_true(text.contains("&lt;script&gt;"))
	assert_true(text.contains("&#124;"))
	assert_true(text.contains("synthetic reason"))
	assert_true(text.contains("待作者确认"))
	assert_true(text.contains(run.run_id))
	assert_false(result.runs[0].human.willing_again)
	assert_null(result.fixed_task_accuracy[0].once_explained_three_of_four)
