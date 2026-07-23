import argparse
import csv
import json
import logging
from io import StringIO

import boto3

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
s3 = boto3.client("s3")


def read_header(bucket: str, key: str) -> set[str]:
    obj = s3.get_object(Bucket=bucket, Key=key)
    first_line = obj["Body"].read(8192).decode("utf-8", errors="replace").splitlines()[0]
    return set(next(csv.reader(StringIO(first_line))))


def validate_file(bucket: str, key: str, dataset: str, required_columns: dict) -> None:
    header = read_header(bucket, key)
    missing = set(required_columns[dataset]) - header
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
    parser.add_argument(
        "--required_columns",
        required=True,
        help="JSON object mapping dataset name (songs/users/streams) to a list of required column names",
    )
    args, _ = parser.parse_known_args()

    required_columns = json.loads(args.required_columns)

    validate_file(args.bucket, args.songs_key, "songs", required_columns)
    validate_file(args.bucket, args.users_key, "users", required_columns)

    stream_keys = list_stream_files(args.bucket, args.streams_prefix)
    if not stream_keys:
        # A redundant/duplicate trigger can fire after a previous run already
        # archived the batch. There is simply nothing to process, which is not
        # an error — exit successfully so the pipeline ends cleanly (no false
        # failure alert). Downstream Glue jobs guard for the same empty case.
        logging.info("No stream CSV files at s3://%s/%s; nothing to process.", args.bucket, args.streams_prefix)
        return
    for key in stream_keys:
        validate_file(args.bucket, key, "streams", required_columns)

    logging.info("Validation completed successfully for %d stream file(s).", len(stream_keys))


if __name__ == "__main__":
    main()
