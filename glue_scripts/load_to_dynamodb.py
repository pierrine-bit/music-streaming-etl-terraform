"""Glue Python Shell job: load the transform's JSON output into DynamoDB."""
import argparse
import json
import logging
from decimal import Decimal

import boto3
from botocore.config import Config

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

# Adaptive retries back off on DynamoDB throttling when writing bursts.
_cfg = Config(retries={"max_attempts": 8, "mode": "adaptive"})
s3 = boto3.client("s3", config=_cfg)
dynamodb = boto3.resource("dynamodb", config=_cfg)


def decimalize(value):
    if isinstance(value, float):
        return Decimal(str(value))
    if isinstance(value, dict):
        return {k: decimalize(v) for k, v in value.items()}
    if isinstance(value, list):
        return [decimalize(v) for v in value]
    return value


def iter_json_records(bucket: str, prefix: str):
    if not prefix.endswith("/"):
        prefix += "/"
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            if not obj["Key"].endswith(".json"):
                continue
            body = s3.get_object(Bucket=bucket, Key=obj["Key"])["Body"].read().decode("utf-8")
            for line in body.splitlines():
                if line.strip():
                    yield decimalize(json.loads(line))


def load_table(bucket: str, prefix: str, table_name: str) -> int:
    table = dynamodb.Table(table_name)
    count = 0
    with table.batch_writer() as batch:
        for item in iter_json_records(bucket, prefix):
            batch.put_item(Item=item)
            count += 1
    log.info("Loaded %d item(s) into %s", count, table_name)
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--processed_prefix", required=True)
    parser.add_argument("--genre_kpis_prefix", required=True)
    parser.add_argument("--top_songs_prefix", required=True)
    parser.add_argument("--top_genres_prefix", required=True)
    parser.add_argument("--genre_table", required=True)
    parser.add_argument("--top_songs_table", required=True)
    parser.add_argument("--top_genres_table", required=True)
    args, _ = parser.parse_known_args()

    base = args.processed_prefix.rstrip("/")
    load_table(args.bucket, f"{base}/{args.genre_kpis_prefix}/", args.genre_table)
    load_table(args.bucket, f"{base}/{args.top_songs_prefix}/", args.top_songs_table)
    load_table(args.bucket, f"{base}/{args.top_genres_prefix}/", args.top_genres_table)


if __name__ == "__main__":
    main()
