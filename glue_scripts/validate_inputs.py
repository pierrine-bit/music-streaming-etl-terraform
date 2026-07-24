"""Glue Python Shell job: validate that reference and stream files have the required columns."""
import argparse
import csv
import json
import logging
from io import StringIO

import boto3
from botocore.config import Config

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

s3 = boto3.client("s3", config=Config(retries={"max_attempts": 5, "mode": "standard"}))


def read_header(bucket: str, key: str) -> set[str]:
    obj = s3.get_object(Bucket=bucket, Key=key)
    first_line = obj["Body"].read(8192).decode("utf-8", errors="replace").splitlines()[0]
    return set(next(csv.reader(StringIO(first_line))))


def validate_file(bucket: str, key: str, dataset: str, required_columns: dict) -> None:
    missing = set(required_columns[dataset]) - read_header(bucket, key)
    if missing:
        raise ValueError(f"{key} is missing required columns: {sorted(missing)}")
    log.info("Validated %s", key)


def list_stream_files(bucket: str, prefix: str) -> list[str]:
    if not prefix.endswith("/"):
        prefix += "/"
    keys = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        keys += [o["Key"] for o in page.get("Contents", []) if o["Key"].endswith(".csv")]
    return keys


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--streams_prefix", required=True)
    parser.add_argument("--songs_key", required=True)
    parser.add_argument("--users_key", required=True)
    parser.add_argument("--required_columns", required=True)
    args, _ = parser.parse_known_args()

    required_columns = json.loads(args.required_columns)
    validate_file(args.bucket, args.songs_key, "songs", required_columns)
    validate_file(args.bucket, args.users_key, "users", required_columns)

    # No stream files means a duplicate trigger fired after a prior run archived
    # the batch: nothing to process, so exit cleanly rather than fail.
    stream_keys = list_stream_files(args.bucket, args.streams_prefix)
    if not stream_keys:
        log.info("No stream files at s3://%s/%s; nothing to process.", args.bucket, args.streams_prefix)
        return
    for key in stream_keys:
        validate_file(args.bucket, key, "streams", required_columns)
    log.info("Validation passed for %d stream file(s).", len(stream_keys))


if __name__ == "__main__":
    main()
