"""Przelicza metryki demo z datasets/ i zapisuje datasets/derived/demo_metrics.json.

Uruchamiac po kazdej regeneracji danych (generate_datasets.py) oraz po zmianie
kalibracji KIS w notebooks/02_situation_index.py. Liczby z tego pliku sa cytowane
w README.md, DEMO_SCRIPT.md, ai/DATA_AGENT.md, activator/RULES.md i fabric-app/*.
"""

from __future__ import annotations

import collections
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "datasets"
DERIVED = DATA / "derived"


def stream(name: str):
    with open(DATA / f"{name}.jsonl", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                yield json.loads(line)


def main() -> None:
    m: dict = {}

    alarm_gminas = set()
    gauge_peak: dict = {}
    for e in stream("hydro_readings"):
        if e["level_cm"] >= e["alarm_level_cm"]:
            alarm_gminas.add(e["gmina_code"])
        cur = gauge_peak.get(e["gauge_id"])
        if cur is None or e["level_cm"] > cur["level_cm"]:
            gauge_peak[e["gauge_id"]] = {"level_cm": e["level_cm"], "at": e["timestamp"], "gmina": e["gmina_code"]}
    m["alarm_gminas"] = len(alarm_gminas)

    inc_total = 0
    affected = 0
    p1 = 0
    inc_types: collections.Counter = collections.Counter()
    for e in stream("incident_reports"):
        inc_total += 1
        affected += e.get("affected_people", 0)
        if e.get("priority") == 1:
            p1 += 1
        inc_types[e["event_type"]] += 1
    m["incidents_total"] = inc_total
    m["affected_people_total"] = affected
    m["incidents_priority1"] = p1
    m["incident_types_top"] = inc_types.most_common(5)

    pwr_hour: collections.Counter = collections.Counter()
    pwr_day: collections.Counter = collections.Counter()
    for e in stream("power_grid_events"):
        pwr_hour[e["timestamp"][:13]] += e["customers_offline"]
        pwr_day[e["timestamp"][:10]] += e["customers_offline"]
    hpk = pwr_hour.most_common(1)[0]
    dpk = pwr_day.most_common(1)[0]
    m["power_peak_hour"] = {"hour": hpk[0], "customers_offline": hpk[1]}
    m["power_peak_day"] = {"day": dpk[0], "customers_offline": dpk[1]}

    tel_events = 0
    min_cov = 100.0
    for e in stream("telecom_events"):
        tel_events += 1
        min_cov = min(min_cov, e["coverage_pct"])
    m["telecom_events"] = tel_events
    m["telecom_min_coverage_pct"] = round(min_cov, 1)

    ev_latest: dict = {}
    ev_day: collections.Counter = collections.Counter()
    for e in stream("evacuation_status"):
        g = e["gmina_code"]
        cur = ev_latest.get(g)
        if cur is None or e["timestamp"] > cur["timestamp"]:
            ev_latest[g] = e
        ev_day[e["timestamp"][:10]] = max(ev_day[e["timestamp"][:10]], e["people_count"])
    m["evacuated_latest_total"] = sum(e["people_count"] for e in ev_latest.values())
    evd = max(ev_day.items(), key=lambda kv: kv[1])
    m["evacuated_peak_gmina_day"] = {"day": evd[0], "people": evd[1]}

    media_total = 0
    disinfo = 0
    disinfo_reach = 0
    reach = 0
    for e in stream("media_signals"):
        media_total += 1
        reach += e["reach"]
        if e["disinformation_flag"]:
            disinfo += 1
            disinfo_reach += e["reach"]
    m["media_signals_total"] = media_total
    m["media_reach_total"] = reach
    m["disinfo_signals"] = disinfo
    m["disinfo_reach"] = disinfo_reach

    country = list(csv.DictReader(open(DERIVED / "kis_daily_country.csv", encoding="utf-8")))
    peak = max(country, key=lambda r: float(r["max_local_kis"]))
    m["kis_peak"] = {
        "day": peak["date"],
        "max_local_kis": float(peak["max_local_kis"]),
        "kis_country": float(peak["kis_country"]),
        "gminas_over_45": int(peak["gminas_over_45"]),
        "gminas_over_85": int(peak["gminas_over_85"]),
    }
    m["kis_country_range"] = [
        min(float(r["kis_country"]) for r in country),
        max(float(r["kis_country"]) for r in country),
    ]

    rec = list(csv.DictReader(open(DERIVED / "escalation_recommendations_voivodeship.csv", encoding="utf-8")))
    m["recommendations_by_level"] = dict(collections.Counter(r["recommended_level"] for r in rec))

    peaks = sorted(gauge_peak.items(), key=lambda kv: kv[1]["at"])
    m["gauge_peaks"] = [{"gauge_id": k, **v} for k, v in peaks[:8]]

    DERIVED.mkdir(exist_ok=True)
    out = DERIVED / "demo_metrics.json"
    out.write_text(json.dumps(m, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Zapisano {out}")
    for k, v in m.items():
        if not isinstance(v, list):
            print(f"  {k}: {v}".encode("ascii", "replace").decode("ascii"))


if __name__ == "__main__":
    main()
