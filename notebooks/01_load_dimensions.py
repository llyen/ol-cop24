# CELL
# 📥 Ładowanie wymiarów COP-24 do Lakehouse Delta

# CELL
from pyspark.sql import functions as F
base = "Files/datasets"
dimensions = ["dim_voivodeship", "dim_powiat", "dim_gmina", "dim_hazard", "dim_institution", "dim_spo", "dim_river_gauge"]

# CELL
for name in dimensions:
    df = spark.read.option("header", True).option("encoding", "UTF-8").csv(f"{base}/{name}.csv")
    df = df.withColumn("ingested_at", F.current_timestamp())
    df.write.mode("overwrite").format("delta").saveAsTable(name)
    print(name, df.count())
