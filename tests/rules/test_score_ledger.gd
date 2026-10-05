extends GutTest

func test_lengths_use_confirmed_formula() -> void:
	var expected: Array[int] = [50, 66, 84, 104, 126, 150]
	for index: int in range(expected.size()):
		assert_eq(ScoreLedger.calculate_base(index + 5), expected[index])
	assert_eq(ScoreLedger.calculate_base(4), 0)

func test_multiplier_extra_and_event_floor() -> void:
	var ledger: ScoreLedger = ScoreLedger.new()
	assert_eq(ledger.commit(5, 1.2, 30).final_score, 90)
	assert_eq(ledger.commit(7, 1.5).final_score, 126)
	assert_eq(ledger.commit(5, 1.01).final_score, 50)
	assert_eq(ledger.commit(0, 9.0, 30, &"extra").final_score, 30)
	assert_eq(ledger.total, 296)

func test_independent_and_crossed_groups_score_separately() -> void:
	var independent: ScoreLedger = ScoreLedger.new()
	independent.commit(5)
	independent.commit(5)
	var crossed: ScoreLedger = ScoreLedger.new()
	crossed.commit(9)
	assert_eq(independent.total, 100)
	assert_eq(crossed.total, 126)

func test_entries_are_copies_and_sum_matches_total() -> void:
	var ledger: ScoreLedger = ScoreLedger.new()
	var first: ScoreEntry = ledger.commit(5)
	first.final_score = 999
	ledger.commit(6)
	var entries: Array[ScoreEntry] = ledger.get_entries()
	assert_eq(entries[0].event_id, 1)
	assert_eq(entries[1].event_id, 2)
	assert_eq(entries[0].final_score + entries[1].final_score, ledger.total)
	entries[0].final_score = 888
	assert_eq(ledger.get_entries()[0].final_score, 50)
	assert_eq(ScoreLedger.new().total, 0)
