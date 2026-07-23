import sys

import boto3
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from pyspark.sql import functions as F
from pyspark.sql.window import Window

args = getResolvedOptions(
    sys.argv,
    [
        "bucket",
        "streams_prefix",
        "songs_key",
        "processed_prefix",
        "events_prefix",
        "genre_kpis_prefix",
        "top_songs_prefix",
        "top_genres_prefix",
        "top_n_songs",
        "top_n_genres",
    ],
)

# Redundant/duplicate triggers can fire after a prior run archived the batch.
# If there are no stream files there is nothing to recompute, so exit cleanly
# before paying for Spark startup (matches validate_inputs.py's no-op behaviour).
_streams_prefix = args["streams_prefix"].rstrip("/") + "/"
_listing = boto3.client("s3").list_objects_v2(Bucket=args["bucket"], Prefix=_streams_prefix)
if not any(obj["Key"].endswith(".csv") for obj in _listing.get("Contents", [])):
    print(f"No stream CSV files at s3://{args['bucket']}/{_streams_prefix}; nothing to transform.")
    sys.exit(0)

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
# Only the partitions present in a write are replaced, so appending one batch's
# events never rewrites (or drops) another batch's partitions.
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

bucket = args["bucket"]
streams_path = f"s3://{bucket}/{args['streams_prefix']}/*.csv"
songs_path = f"s3://{bucket}/{args['songs_key']}"
processed = f"s3://{bucket}/{args['processed_prefix']}"
events_path = f"{processed}/{args['events_prefix']}"
top_n_songs = int(args["top_n_songs"])
top_n_genres = int(args["top_n_genres"])

# --- 1. Read and clean the new batch currently under raw/streams/. ---
streams = spark.read.option("header", True).csv(streams_path)
songs = spark.read.option("header", True).csv(songs_path)

streams_clean = (
    streams.withColumn("source_file", F.regexp_extract(F.input_file_name(), r"([^/]+)\.csv$", 1))
    .select(
        "source_file",
        F.col("user_id").cast("long").alias("user_id"),
        F.col("track_id"),
        F.to_timestamp("listen_time").alias("listen_ts"),
    )
    .dropna(subset=["user_id", "track_id", "listen_ts"])
    .withColumn("listen_date", F.to_date("listen_ts").cast("string"))
)

songs_clean = songs.select(
    F.col("track_id"),
    F.col("track_name"),
    F.col("track_genre"),
    F.col("duration_ms").cast("long").alias("duration_ms"),
).dropna(subset=["track_id", "track_genre", "duration_ms"])

new_events = streams_clean.join(songs_clean, on="track_id", how="inner").select(
    "source_file",
    "listen_date",
    "track_genre",
    "user_id",
    "track_id",
    "track_name",
    "duration_ms",
)

# --- 2. Append the batch to the cumulative event store. ---
# Partitioning by source_file makes reprocessing a file idempotent: a retry
# overwrites that file's partition rather than double-counting its plays.
new_events.write.mode("overwrite").partitionBy("source_file").parquet(events_path)

# --- 3. Recompute daily KPIs from the FULL event history. ---
# Reading the accumulated store (not just this batch) keeps unique listeners
# and the top-N rankings correct when a day's data spans multiple batches.
events = spark.read.parquet(events_path)

base = events.groupBy("listen_date", "track_genre").agg(
    F.count("*").alias("listen_count"),
    F.countDistinct("user_id").alias("unique_listeners"),
    F.sum("duration_ms").alias("total_listening_time_ms"),
)

kpis = (
    base.withColumn(
        "avg_listening_time_per_user_ms",
        F.when(F.col("unique_listeners") > 0, F.col("total_listening_time_ms") / F.col("unique_listeners")).otherwise(F.lit(0)),
    )
    .withColumn("date_genre", F.concat_ws("#", "listen_date", "track_genre"))
    .select(
        "date_genre",
        "listen_date",
        "track_genre",
        "listen_count",
        "unique_listeners",
        "total_listening_time_ms",
        F.round("avg_listening_time_per_user_ms", 2).alias("avg_listening_time_per_user_ms"),
    )
)

song_counts = events.groupBy("listen_date", "track_genre", "track_id", "track_name").agg(F.count("*").alias("listen_count"))
song_window = Window.partitionBy("listen_date", "track_genre").orderBy(F.desc("listen_count"), F.asc("track_name"))
top_songs = (
    song_counts.withColumn("rank", F.row_number().over(song_window))
    .filter(F.col("rank") <= top_n_songs)
    .withColumn("date_genre", F.concat_ws("#", "listen_date", "track_genre"))
    .select("date_genre", "rank", "listen_date", "track_genre", "track_id", "track_name", "listen_count")
)

genre_window = Window.partitionBy("listen_date").orderBy(F.desc("listen_count"), F.asc("track_genre"))
top_genres = (
    base.select("listen_date", "track_genre", "listen_count")
    .withColumn("rank", F.row_number().over(genre_window))
    .filter(F.col("rank") <= top_n_genres)
    .select("listen_date", "rank", "track_genre", "listen_count")
)

# KPI outputs cover every date in the store, so overwriting the whole prefix is
# correct (and the DynamoDB load below re-puts each item idempotently).
outputs = {
    args["genre_kpis_prefix"]: kpis,
    args["top_songs_prefix"]: top_songs,
    args["top_genres_prefix"]: top_genres,
}
for subprefix, df in outputs.items():
    df.coalesce(1).write.mode("overwrite").json(f"{processed}/{subprefix}/")
