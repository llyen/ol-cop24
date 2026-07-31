# CELL
# 🚦 Rekomendacja poziomu reagowania
#
# Logika:
# - KIS <25: poziom gminy, monitorowanie.
# - KIS 25–44.9: rekomendacja powiatu, bo problem przekracza rutynę gminną.
# - KIS 45–64.9: rekomendacja wojewody, bo rośnie skala regionalna.
# - KIS 65–84.9: minister wiodący, bo pojawia się odpowiedzialność resortowa.
# - KIS ≥85: RZZK, gdy ryzyko ma charakter wieloresortowy albo brakuje zasobów.
# Rekomendacja nie jest decyzją administracyjną. Służy do uzasadnienia rozmowy
# z człowiekiem decyzyjnym i do wskazania właściwych SPO.

# CELL
try:
    spark  # type: ignore[name-defined]
    FABRIC = True
except NameError:
    FABRIC = False

# CELL
if FABRIC:
    from pyspark.sql import functions as F
    kis = spark.table("kis_gmina")
    rec = kis.withColumn(
        "recommended_level",
        F.when(F.col("kis") >= 85, "RZZK").when(F.col("kis") >= 65, "minister wiodący").when(F.col("kis") >= 45, "wojewoda").when(F.col("kis") >= 25, "powiat").otherwise("gmina")
    ).withColumn(
        "recommended_spo",
        F.when(F.col("recommended_level") == "RZZK", "SPO-1;SPO-2;SPO-3;SPO-10").when(F.col("recommended_level") == "minister wiodący", "SPO-12;SPO-3").otherwise("SPO-3;SPO-12")
    ).withColumn(
        "explanation",
        F.concat(F.lit("KIS="), F.col("kis"), F.lit("; hydro="), F.col("hydro_score"), F.lit(", incydenty="), F.col("incident_score"), F.lit(", energia="), F.col("power_score"), F.lit(", telekom="), F.col("telecom_score"))
    )
    rec.write.mode("overwrite").format("delta").saveAsTable("escalation_recommendations")
    display(rec.orderBy(F.desc("kis")).limit(20))

# CELL
if not FABRIC:
    import csv
    from pathlib import Path
    root = Path(__file__).resolve().parents[1]
    derived = root / "datasets" / "derived"
    rows = []
    for r in csv.DictReader(open(derived / "kis_daily_voivodeship.csv", encoding="utf-8")):
        kis = float(r["max_kis"])
        if kis < 25:
            continue
        level = "RZZK" if kis >= 85 else "minister wiodący" if kis >= 65 else "wojewoda" if kis >= 45 else "powiat"
        spo = "SPO-1;SPO-2;SPO-3;SPO-10" if level == "RZZK" else "SPO-12;SPO-3"
        rows.append({"date": r["date"], "voivodeship_code": r["voivodeship_code"], "voivodeship_name": r["voivodeship_name"], "max_kis": kis, "recommended_level": level, "recommended_spo": spo, "explanation": f"Max lokalny KIS={kis}; rekomendowany poziom {level}; SPO {spo}"})
    with open(derived / "escalation_recommendations_voivodeship.csv", "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
    print("Wrote", derived / "escalation_recommendations_voivodeship.csv", len(rows), "rows")
