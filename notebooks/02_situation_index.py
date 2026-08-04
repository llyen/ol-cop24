# CELL
# 🧮 Krajowy Indeks Sytuacji (KIS) 0–100
#
# Metoda:
# - KIS jest syntetycznym indeksem demonstracyjnym, który porządkuje wiele strumieni
#   w jedną skalę decyzyjną. Nie jest formalnym algorytmem państwowym.
# - Składowe i wagi:
#   hydro 30% — bezpośrednie zagrożenie powodziowe i przekroczenia progów,
#   incydenty 25% — realny wpływ na ludność i obciążenie służb,
#   energia 15% — kaskada infrastruktury krytycznej Z07,
#   telekom 10% — ryzyko utraty alarmowania i łączności Z12,
#   ewakuacja 10% — skala działań ochrony ludności,
#   zasoby 10% — obciążenie sił i środków w województwie (PSP, WOT, pompy,
#     agregaty, śmigłowce), czyli sygnał, że region jest już w fazie intensywnego reagowania.
# - Normalizacja jest celowo prosta i wyjaśnialna: każda składowa jest sprowadzona
#   do 0–100, a wynik jest obcięty do 100. W prawdziwym wdrożeniu normalizację
#   zatwierdza właściciel procesu i kalibruje na danych historycznych.
#
# Kalibracja (2026-08-04): dzielniki poniżej to poziom, przy którym składowa osiąga
# 100 pkt. Dobrane z faktycznego rozkładu danych scenariusza tak, aby kulminacja
# (2026-09-17) punktowo przebijała próg 85 = zwołanie RZZK, zamiast zatrzymywać się
# poniżej progu przy każdym możliwym przebiegu. Skrypt: notebooks/_calibrate.py.

# CELL
INC_DIV = 5.0     # zgłoszeń na gminę/dobę (p95 = 4, max = 8)
PWR_DIV = 1200.0  # odbiorców bez prądu na gminę/dobę (mediana 1027, max 10 749)
EV_DIV = 250.0    # ewakuowanych na gminę/dobę (p90 = 414, max 604)
RES_DIV = 900.0   # punktów obciążenia sił i środków na województwo/dobę (mediana 132, max 2390)

# CELL
try:
    spark  # type: ignore[name-defined]
    FABRIC = True
except NameError:
    FABRIC = False

# CELL
if FABRIC:
    from pyspark.sql import functions as F
    hydro = spark.table("hydro_readings").withColumn("hydro_score", F.when(F.col("level_cm") >= F.col("alarm_level_cm"), 100).when(F.col("level_cm") >= F.col("warning_level_cm"), 60).otherwise(15))
    hydro_g = hydro.groupBy("gmina_code").agg(F.max("hydro_score").alias("hydro_score"))
    inc = spark.table("incident_reports").groupBy("gmina_code").agg(F.least(F.lit(100.0), F.count("*") / F.lit(INC_DIV) * 100).alias("incident_score"), F.sum("affected_people").alias("affected_people"))
    pwr = spark.table("power_grid_events").groupBy("gmina_code").agg(F.least(F.lit(100.0), F.sum("customers_offline") / F.lit(PWR_DIV) * 100).alias("power_score"))
    tel = spark.table("telecom_events").groupBy("gmina_code").agg((100 - F.min("coverage_pct")).alias("telecom_score"))
    ev = spark.table("evacuation_status").groupBy("gmina_code").agg(F.least(F.lit(100.0), F.max("people_count") / F.lit(EV_DIV) * 100).alias("evac_score"))
    res_load = (F.col("psp_units") * 3 + F.col("wot_soldiers") * 0.4 + F.col("pumps") * 5 + F.col("generators") * 4 + F.col("helicopters") * 25)
    res = spark.table("resource_deployment").withColumn("res_load", res_load).groupBy("voivodeship_code").agg(F.least(F.lit(100.0), F.max("res_load") / F.lit(RES_DIV) * 100).alias("resource_score"))
    g = spark.table("dim_gmina").select("gmina_code", "powiat_code")
    p = spark.table("dim_powiat").select("powiat_code", "voivodeship_code")
    score = g.join(p, "powiat_code").join(hydro_g, "gmina_code", "left").join(inc, "gmina_code", "left").join(pwr, "gmina_code", "left").join(tel, "gmina_code", "left").join(ev, "gmina_code", "left").join(res, "voivodeship_code", "left").fillna(0)
    score = score.withColumn("kis", F.least(F.lit(100), F.round(0.30*F.col("hydro_score") + 0.25*F.col("incident_score") + 0.15*F.col("power_score") + 0.10*F.col("telecom_score") + 0.10*F.col("evac_score") + 0.10*F.col("resource_score"), 1)))
    score = score.drop("voivodeship_code")
    score.write.mode("overwrite").format("delta").saveAsTable("kis_gmina")
    kis_powiat = score.groupBy("powiat_code").agg(F.round(F.avg("kis"), 1).alias("kis"), F.max("kis").alias("max_kis"))
    kis_powiat.write.mode("overwrite").format("delta").saveAsTable("kis_powiat")
    kis_voiv = kis_powiat.join(p, "powiat_code").groupBy("voivodeship_code").agg(F.round(F.avg("kis"), 1).alias("kis"), F.max("max_kis").alias("max_kis"))
    kis_voiv.write.mode("overwrite").format("delta").saveAsTable("kis_voivodeship")
    kis_country = kis_voiv.agg(F.round(F.avg("kis"), 1).alias("kis_country"), F.max("max_kis").alias("max_local_kis"))
    kis_country.write.mode("overwrite").format("delta").saveAsTable("kis_country")
    display(kis_country)

# CELL
if not FABRIC:
    import csv, json, collections, datetime
    from pathlib import Path
    root = Path(__file__).resolve().parents[1]
    data = root / "datasets"
    derived = data / "derived"
    derived.mkdir(exist_ok=True)
    vo = {r["voivodeship_code"]: r for r in csv.DictReader(open(data / "dim_voivodeship.csv", encoding="utf-8"))}
    powiat = {r["powiat_code"]: r for r in csv.DictReader(open(data / "dim_powiat.csv", encoding="utf-8"))}
    gminas = {r["gmina_code"]: r for r in csv.DictReader(open(data / "dim_gmina.csv", encoding="utf-8"))}
    g2v = {g: powiat[r["powiat_code"]]["voivodeship_code"] for g, r in gminas.items()}
    days = [(datetime.date(2026, 9, 12) + datetime.timedelta(days=i)).isoformat() for i in range(14)]
    hydro = collections.defaultdict(dict)
    for line in open(data / "hydro_readings.jsonl", encoding="utf-8"):
        e = json.loads(line); day = e["timestamp"][:10]
        s = 100 if e["level_cm"] >= e["alarm_level_cm"] else 60 if e["level_cm"] >= e["warning_level_cm"] else 15
        hydro[day][e["gmina_code"]] = max(hydro[day].get(e["gmina_code"], 0), s)
    inc = collections.defaultdict(lambda: collections.Counter())
    pwr = collections.defaultdict(lambda: collections.Counter())
    tel = collections.defaultdict(dict)
    ev = collections.defaultdict(dict)
    for line in open(data / "incident_reports.jsonl", encoding="utf-8"):
        e = json.loads(line); inc[e["timestamp"][:10]][e["gmina_code"]] += 1
    for line in open(data / "power_grid_events.jsonl", encoding="utf-8"):
        e = json.loads(line); pwr[e["timestamp"][:10]][e["gmina_code"]] += e["customers_offline"]
    for line in open(data / "telecom_events.jsonl", encoding="utf-8"):
        e = json.loads(line); d=e["timestamp"][:10]; g=e["gmina_code"]; tel[d][g] = min(tel[d].get(g, 100), e["coverage_pct"])
    for line in open(data / "evacuation_status.jsonl", encoding="utf-8"):
        e = json.loads(line); d=e["timestamp"][:10]; g=e["gmina_code"]; ev[d][g] = max(ev[d].get(g, 0), e["people_count"])
    res = collections.defaultdict(dict)
    for line in open(data / "resource_deployment.jsonl", encoding="utf-8"):
        e = json.loads(line); d=e["timestamp"][:10]; v=e["voivodeship_code"]
        load = e["psp_units"]*3 + e["wot_soldiers"]*0.4 + e["pumps"]*5 + e["generators"]*4 + e["helicopters"]*25
        res[d][v] = max(res[d].get(v, 0.0), load)
    country, voiv_rows = [], []
    for day in days:
        scores, byv = [], collections.defaultdict(list)
        for g in gminas:
            kis = min(100, round(.30*hydro.get(day,{}).get(g,0) + .25*min(100,inc.get(day,{}).get(g,0)/INC_DIV*100) + .15*min(100,pwr.get(day,{}).get(g,0)/PWR_DIV*100) + .10*(100-tel.get(day,{}).get(g,100)) + .10*min(100,ev.get(day,{}).get(g,0)/EV_DIV*100) + .10*min(100,res.get(day,{}).get(g2v[g],0.0)/RES_DIV*100), 1))
            scores.append(kis); byv[g2v[g]].append(kis)
        country.append({"date": day, "kis_country": round(sum(scores)/len(scores), 1), "max_local_kis": max(scores), "gminas_over_25": sum(s >= 25 for s in scores), "gminas_over_45": sum(s >= 45 for s in scores), "gminas_over_85": sum(s >= 85 for s in scores)})
        for v, arr in byv.items():
            voiv_rows.append({"date": day, "voivodeship_code": v, "voivodeship_name": vo[v]["voivodeship_name"], "kis": round(sum(arr)/len(arr), 1), "max_kis": max(arr)})
    for name, rows in [("kis_daily_country.csv", country), ("kis_daily_voivodeship.csv", voiv_rows)]:
        with open(derived / name, "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
    print("Wrote", derived / "kis_daily_country.csv", "and", derived / "kis_daily_voivodeship.csv")
