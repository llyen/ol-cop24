import csv, json, collections, datetime
from pathlib import Path

root = Path(__file__).resolve().parents[1]
data = root / "datasets"
gminas = {r["gmina_code"]: r for r in csv.DictReader(open(data / "dim_gmina.csv", encoding="utf-8"))}
days = [(datetime.date(2026, 9, 12) + datetime.timedelta(days=i)).isoformat() for i in range(14)]

hydro = collections.defaultdict(dict)
for line in open(data / "hydro_readings.jsonl", encoding="utf-8"):
    e = json.loads(line); d = e["timestamp"][:10]
    s = 100 if e["level_cm"] >= e["alarm_level_cm"] else 60 if e["level_cm"] >= e["warning_level_cm"] else 15
    hydro[d][e["gmina_code"]] = max(hydro[d].get(e["gmina_code"], 0), s)

inc = collections.defaultdict(collections.Counter)
pwr = collections.defaultdict(collections.Counter)
tel = collections.defaultdict(dict)
ev = collections.defaultdict(dict)
for line in open(data / "incident_reports.jsonl", encoding="utf-8"):
    e = json.loads(line); inc[e["timestamp"][:10]][e["gmina_code"]] += 1
for line in open(data / "power_grid_events.jsonl", encoding="utf-8"):
    e = json.loads(line); pwr[e["timestamp"][:10]][e["gmina_code"]] += e["customers_offline"]
for line in open(data / "telecom_events.jsonl", encoding="utf-8"):
    e = json.loads(line); d = e["timestamp"][:10]; g = e["gmina_code"]
    tel[d][g] = min(tel[d].get(g, 100), e["coverage_pct"])
for line in open(data / "evacuation_status.jsonl", encoding="utf-8"):
    e = json.loads(line); d = e["timestamp"][:10]; g = e["gmina_code"]
    ev[d][g] = max(ev[d].get(g, 0), e["people_count"])


def pct(arr, q):
    if not arr:
        return 0
    arr = sorted(arr)
    return arr[min(len(arr) - 1, int(q * len(arr)))]


for label, src in [("incydenty/gmina/doba", inc), ("odbiorcy bez pradu", pwr), ("ewakuowani", ev)]:
    vals = [v for d in days for v in src.get(d, {}).values() if v]
    print(f"{label}: n={len(vals)} max={max(vals)} p99={pct(vals,.99)} p95={pct(vals,.95)} p90={pct(vals,.90)} mediana={pct(vals,.5)}")

telvals = [v for d in days for v in tel.get(d, {}).values()]
print(f"pokrycie telekom: n={len(telvals)} min={min(telvals)} p05={pct(telvals,.05)} mediana={pct(telvals,.5)}")


powiat = {r["powiat_code"]: r for r in csv.DictReader(open(data / "dim_powiat.csv", encoding="utf-8"))}
g2v = {g: powiat[r["powiat_code"]]["voivodeship_code"] for g, r in gminas.items()}
res_raw = collections.defaultdict(dict)
for line in open(data / "resource_deployment.jsonl", encoding="utf-8"):
    e = json.loads(line); d = e["timestamp"][:10]; v = e["voivodeship_code"]
    load = e["psp_units"] * 3 + e["wot_soldiers"] * 0.4 + e["pumps"] * 5 + e["generators"] * 4 + e["helicopters"] * 25
    res_raw[d][v] = max(res_raw[d].get(v, 0), load)
allres = [v for d in res_raw.values() for v in d.values()]
print(f"\nobciazenie zasobow (woj/doba): n={len(allres)} max={max(allres):.0f} p95={pct(allres,.95):.0f} mediana={pct(allres,.5):.0f}")
RES_DIV = 900.0


def simulate(d_inc, d_pwr, d_ev, res):
    out = []
    for day in days:
        for g in gminas:
            rs = res if res else min(100, res_raw.get(day, {}).get(g2v[g], 0) / RES_DIV * 100)
            kis = min(100, round(
                .30 * hydro.get(day, {}).get(g, 0)
                + .25 * min(100, inc.get(day, {}).get(g, 0) / d_inc * 100)
                + .15 * min(100, pwr.get(day, {}).get(g, 0) / d_pwr * 100)
                + .10 * (100 - tel.get(day, {}).get(g, 100))
                + .10 * min(100, ev.get(day, {}).get(g, 0) / d_ev * 100)
                + .10 * rs, 1))
            out.append((day, g, kis))
    return out


for params in [(20, 5000, 1000, 20), (6, 1500, 300, 0), (5, 1200, 250, 0), (4, 1000, 200, 0)]:
    rows = simulate(*params)
    mx = max(r[2] for r in rows)
    over85 = len({(d, g) for d, g, k in rows if k >= 85})
    over65 = len({(d, g) for d, g, k in rows if k >= 65})
    over45 = len({(d, g) for d, g, k in rows if k >= 45})
    gm85 = len({g for _, g, k in rows if k >= 85})
    peak = max(((d, k) for d, _, k in rows), key=lambda x: x[1])
    byday = collections.defaultdict(float)
    for d, _, k in rows:
        byday[d] = max(byday[d], k)
    print(f"\ndzielniki inc={params[0]} pwr={params[1]} ev={params[2]} res={params[3]}")
    print(f"  max={mx} szczyt={peak[0]} par(dzien,gmina)>=85: {over85} >=65: {over65} >=45: {over45} | unikalnych gmin>=85: {gm85}")
    print("  maks. dobowy: " + ", ".join(f"{d[5:]}={v}" for d, v in sorted(byday.items())))
