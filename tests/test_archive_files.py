"""Unit tests for the archive Lambda's move logic (copy-then-delete, skip markers)."""
import archive_files


class _FakeS3:
    """Minimal stand-in for the boto3 S3 client the handler uses."""

    def __init__(self, keys):
        self._keys = keys
        self.copied = []
        self.deleted = []

    def get_paginator(self, _name):
        keys = self._keys

        class _Paginator:
            def paginate(self, **_kwargs):
                return iter([{"Contents": [{"Key": k} for k in keys]}])

        return _Paginator()

    def copy_object(self, Bucket, CopySource, Key):
        self.copied.append((CopySource["Key"], Key))

    def delete_object(self, Bucket, Key):
        self.deleted.append(Key)


def test_moves_files_and_deletes_source(monkeypatch):
    fake = _FakeS3(["raw/streams/streams1.csv", "raw/streams/streams2.csv"])
    monkeypatch.setattr(archive_files, "s3", fake)

    result = archive_files.lambda_handler(
        {"bucket": "b", "source_prefix": "raw/streams", "archive_prefix": "archive", "execution_id": "run1"},
        None,
    )

    assert result["moved_count"] == 2
    assert ("raw/streams/streams1.csv", "archive/run1/streams1.csv") in fake.copied
    assert "raw/streams/streams1.csv" in fake.deleted


def test_skips_directory_markers(monkeypatch):
    fake = _FakeS3(["raw/streams/", "raw/streams/streams1.csv"])
    monkeypatch.setattr(archive_files, "s3", fake)

    result = archive_files.lambda_handler(
        {"bucket": "b", "source_prefix": "raw/streams", "execution_id": "run1"}, None
    )

    assert result["moved_count"] == 1
    assert fake.deleted == ["raw/streams/streams1.csv"]
