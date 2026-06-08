import boto3
import os
from datetime import datetime, timezone

s3 = boto3.client("s3")


def lambda_handler(event, context):
    bucket = event.get("bucket") or os.environ["BUCKET"]
    source_prefix = event.get("source_prefix", os.environ.get("SOURCE_PREFIX", "raw/streams"))
    archive_prefix = event.get("archive_prefix", os.environ.get("ARCHIVE_PREFIX", "archive"))
    execution_id = event.get("execution_id", datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))

    if not source_prefix.endswith("/"):
        source_prefix += "/"
    if not archive_prefix.endswith("/"):
        archive_prefix += "/"

    moved = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=source_prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if key.endswith("/"):
                continue
            relative = key[len(source_prefix):]
            dest_key = f"{archive_prefix}{execution_id}/{relative}"
            s3.copy_object(Bucket=bucket, CopySource={"Bucket": bucket, "Key": key}, Key=dest_key)
            s3.delete_object(Bucket=bucket, Key=key)
            moved.append({"from": key, "to": dest_key})

    return {"moved_count": len(moved), "moved": moved}
