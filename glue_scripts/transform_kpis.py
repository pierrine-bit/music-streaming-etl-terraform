import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from pyspark.sql import functions as F
from pyspark.sql.window import Window

args = getResolvedOptions(sys.argv, ["bucket", "streams_prefix", "songs_key", "users_key", "processed_prefix"])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

bucket = args["bucket"]
streams_path = f"s3://{bucket}/{args['streams_prefix']}/*.csv"
songs_path = f"s3://{bucket}/{args['songs_key']}"
processed = f"s3://{bucket}/{args['processed_prefix']}"

streams = spark.read.option("header", True).csv(streams_path)
songs = spark.read.option("header", True).csv(songs_path)

streams_clean = (
    streams.select(
        F.col("user_id").cast("long").alias("user_id"),
        F.col("track_id"),
        F.to_timestamp("listen_time").alias("listen_ts"),
    )
    .dropna(subset=["user_id", "track_id", "listen_ts"])
    .withColumn("listen_date", F.to_date("listen_ts").cast("string"))
)

songs_clean = (
    songs.select(
        F.col("track_id"),
        F.col("track_name"),
        F.col("track_genre"),
        F.col("duration_ms").cast("long").alias("duration_ms"),
    )
    .dropna(subset=["track_id", "track_genre", "duration_ms"])
)

joined = streams_clean.join(songs_clean, on="track_id", how="inner")

base = joined.groupBy("listen_date", "track_genre").agg(
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

song_counts = joined.groupBy("listen_date", "track_genre", "track_id", "track_name").agg(F.count("*").alias("listen_count"))
song_window = Window.partitionBy("listen_date", "track_genre").orderBy(F.desc("listen_count"), F.asc("track_name"))
top_songs = (
    song_counts.withColumn("rank", F.row_number().over(song_window))
    .filter(F.col("rank") <= 3)
    .withColumn("date_genre", F.concat_ws("#", "listen_date", "track_genre"))
    .select("date_genre", "rank", "listen_date", "track_genre", "track_id", "track_name", "listen_count")
)

genre_window = Window.partitionBy("listen_date").orderBy(F.desc("listen_count"), F.asc("track_genre"))
top_genres = (
    base.select("listen_date", "track_genre", "listen_count")
    .withColumn("rank", F.row_number().over(genre_window))
    .filter(F.col("rank") <= 5)
    .select("listen_date", "rank", "track_genre", "listen_count")
)

for name, df in [("genre_daily_kpis", kpis), ("top_songs", top_songs), ("top_genres", top_genres)]:
    df.coalesce(1).write.mode("overwrite").json(f"{processed}/{name}/")
