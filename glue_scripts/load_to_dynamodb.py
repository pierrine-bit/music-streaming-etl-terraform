import argparse
import json
import logging
from decimal import Decimal

import boto3

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")


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
            key = obj["Key"]
            if not key.endswith(".json"):
                continue
            body = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode("utf-8")
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
    logging.info("Loaded %d item(s) into %s", count, table_name)
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--processed_prefix", required=True)
    parser.add_argument("--genre_table", required=True)
    parser.add_argument("--top_songs_table", required=True)
    parser.add_argument("--top_genres_table", required=True)
    args, _ = parser.parse_known_args()

    base = args.processed_prefix.rstrip("/")
    load_table(args.bucket, f"{base}/genre_daily_kpis/", args.genre_table)
    load_table(args.bucket, f"{base}/top_songs/", args.top_songs_table)
    load_table(args.bucket, f"{base}/top_genres/", args.top_genres_table)


if __name__ == "__main__":
    main()
