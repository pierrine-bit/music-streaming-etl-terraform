"""Unit tests for the validation job's required-column checks."""
import pytest

import validate_inputs as v

REQUIRED = {
    "songs": ["track_id", "track_name", "duration_ms", "track_genre"],
    "users": ["user_id", "user_name", "user_age", "user_country", "created_at"],
    "streams": ["user_id", "track_id", "listen_time"],
}


def test_missing_required_column_raises(monkeypatch):
    # Header is missing "listen_time" -> validation must fail.
    monkeypatch.setattr(v, "read_header", lambda bucket, key: {"user_id", "track_id"})
    with pytest.raises(ValueError, match="missing required columns"):
        v.validate_file("bucket", "raw/streams/s1.csv", "streams", REQUIRED)


def test_all_required_columns_present_passes(monkeypatch):
    monkeypatch.setattr(v, "read_header", lambda bucket, key: {"user_id", "track_id", "listen_time"})
    # Should not raise.
    v.validate_file("bucket", "raw/streams/s1.csv", "streams", REQUIRED)


def test_extra_columns_are_allowed(monkeypatch):
    # Superset of required columns is fine.
    monkeypatch.setattr(v, "read_header", lambda bucket, key: {"user_id", "track_id", "listen_time", "device", "region"})
    v.validate_file("bucket", "raw/streams/s1.csv", "streams", REQUIRED)


def test_error_message_lists_missing_columns(monkeypatch):
    monkeypatch.setattr(v, "read_header", lambda bucket, key: {"track_id"})
    with pytest.raises(ValueError) as exc:
        v.validate_file("bucket", "raw/reference/songs.csv", "songs", REQUIRED)
    msg = str(exc.value)
    assert "duration_ms" in msg and "track_genre" in msg and "track_name" in msg
