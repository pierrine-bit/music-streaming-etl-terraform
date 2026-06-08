import argparse
import csv
import logging
from io import StringIO

import boto3

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
s3 = boto3.client("s3")

REQUIRED = {
    "songs": {"track_id", "track_name", "duration_ms", "track_genre"},
    "users": {"user_id", "user_name", "user_age", "user_country", "created_at"},
    "streams": {"user_id", "track_id", "listen_time"},
}


def read_header(bucket: str, key: str) -> set[str]:
    obj = s3.get_object(Bucket=bucket, Key=key)
    first_line = obj["Body"].read(8192).decode("utf-8", errors="replace").splitlines()[0]
    return set(next(csv.reader(StringIO(first_line))))


def validate_file(bucket: str, key: str, dataset: str) -> None:
    header = read_header(bucket, key)
    missing = REQUIRED[dataset] - header
    if missing:
        raise ValueError(f"{key} is missing required columns: {sorted(missing)}")
    logging.info("Validated %s with columns %s", key, sorted(header))


def list_stream_files(bucket: str, prefix: str) -> list[str]:
    if not prefix.endswith("/"):
        prefix += "/"
    keys = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if key.endswith(".csv"):
                keys.append(key)
    return keys


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--streams_prefix", required=True)
    parser.add_argument("--songs_key", required=True)
    parser.add_argument("--users_key", required=True)
    args, _ = parser.parse_known_args()

    validate_file(args.bucket, args.songs_key, "songs")
    validate_file(args.bucket, args.users_key, "users")

    stream_keys = list_stream_files(args.bucket, args.streams_prefix)
    if not stream_keys:
        raise ValueError(f"No stream CSV files found at s3://{args.bucket}/{args.streams_prefix}")
    for key in stream_keys:
        validate_file(args.bucket, key, "streams")

    logging.info("Validation completed successfully for %d stream file(s).", len(stream_keys))


if __name__ == "__main__":
    main()
