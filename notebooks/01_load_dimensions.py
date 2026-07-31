# CELL
# 📥 Ładowanie wymiarów COP-24 do Lakehouse Delta

# CELL
from pyspark.sql import functions as F
from pyspark.sql import types as T
base = "Files/datasets"
dimensions = ["dim_voivodeship", "dim_powiat", "dim_gmina", "dim_hazard", "dim_institution", "dim_spo", "dim_river_gauge"]

# Typy trzeba narzucic jawnie. Czytanie CSV bez schematu daje same kolumny tekstowe,
# a wtedy Direct Lake widzi lat/lon jako tekst i wizualizacja mapy odmawia dzialania
# ("Something's wrong with one or more fields"). inferSchema bywa niestabilny miedzy
# uruchomieniami, dlatego rzutujemy znane kolumny liczbowe wprost.
numeric_columns = {
    "lat": T.DoubleType(),
    "lon": T.DoubleType(),
    "population": T.LongType(),
    "warning_level_cm": T.IntegerType(),
    "alarm_level_cm": T.IntegerType(),
    "capacity": T.IntegerType(),
}

# CELL
for name in dimensions:
    df = spark.read.option("header", True).option("encoding", "UTF-8").csv(f"{base}/{name}.csv")
    for column, dtype in numeric_columns.items():
        if column in df.columns:
            df = df.withColumn(column, F.col(column).cast(dtype))
    df = df.withColumn("ingested_at", F.current_timestamp())
    df.write.mode("overwrite").option("overwriteSchema", "true").format("delta").saveAsTable(name)
    typy = {c: t for c, t in df.dtypes if c in numeric_columns}
    print(name, df.count(), typy)
