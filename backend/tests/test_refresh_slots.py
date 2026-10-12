from datetime import datetime, timezone

import refresh_slots

UTC = timezone.utc


def _at(hour, minute=0, day=12):
    return datetime(2026, 10, day, hour, minute, tzinfo=UTC)


def test_books_the_next_overnight_slot():
    assert refresh_slots.next_wait_seconds(_at(7, 30)) == 53 * 60


def test_a_run_right_at_a_slot_books_the_following_one():
    assert refresh_slots.next_wait_seconds(_at(8, 23)) == 60 * 60


def test_the_evening_sweep_books_tomorrow_morning():
    assert refresh_slots.next_wait_seconds(_at(20, 30)) == (10 * 60 + 53) * 60


def test_a_capped_hop_overnight_is_not_an_attempt():
    hop = _at(2, 8, day=13)
    assert refresh_slots.current_slot(hop) is None
    assert refresh_slots.next_wait_seconds(hop) == (5 * 60 + 15) * 60


def test_a_late_wake_still_counts_as_its_slot():
    assert refresh_slots.current_slot(_at(9, 50)) == _at(9, 23)


def test_only_the_evening_sweep_is_final():
    assert refresh_slots.is_final_attempt(_at(20, 25))
    assert refresh_slots.is_final_attempt(_at(21, 40))
    assert not refresh_slots.is_final_attempt(_at(17, 30))
    assert not refresh_slots.is_final_attempt(_at(23, 0))
