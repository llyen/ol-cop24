# CELL
# # 01b - Ladowanie strumieni zdarzen do Lakehouse
#
# Notatnik wczytuje pliki JSONL z `Files/streams/` do tabel Delta w Lakehouse
# `OL_COP24_Lakehouse`. Tabele sa zrodlem dla notatnika `02_situation_index`
# (Komponentowy Indeks Sytuacyjny) w wariancie batch.
#
# Dane te sa rownolegle dostepne w Eventhouse (analityka strumieniowa,
# Real-Time Dashboard, Activator). Warstwa Delta sluzy modelowi semantycznemu
# i raportom Power BI.

# CELL
from pyspark.sql import functions as F

STREAMS = [
    "hydro_readings",
    "weather_observations",
    "incident_reports",
    "power_grid_events",
    "telecom_events",
    "evacuation_status",
    "resource_deployment",
    "media_signals",
    "escalation_events",
]

BASE = "Files/streams"

# CELL
for name in STREAMS:
    path = f"{BASE}/{name}.jsonl"
    df = spark.read.json(path)
    if "timestamp" in df.columns:
        df = df.withColumn("timestamp", F.to_timestamp("timestamp"))
    df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(name)
    print(f"{name}: {df.count()} wierszy")

# CELL
for name in STREAMS:
    print(name, spark.table(name).count())
