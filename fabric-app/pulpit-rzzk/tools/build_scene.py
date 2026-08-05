"""Buduje statyczna scene demo (public/data/scene.json) z datasets/ repozytorium ol-cop24.

Dlaczego z plikow, a nie z Eventhouse:
- Eventhouse przechowuje wylacznie okno ostatniego odtwarzania (replay czysci tabele
  i pisze biezacym czasem), wiec nie zawiera pelnej sceny D-3..D+10.
- datasets/ to deterministyczne zrodlo, z ktorego zasilany jest Lakehouse i Eventstream,
  wiec liczby w aplikacji zgadzaja sie z dashboardem i notatnikami.

Formula KIS jest skopiowana z notebooks/02_situation_index.py (te same wagi i normalizacja),
zeby aplikacja nie pokazywala innych wartosci niz Lakehouse.

Uruchomienie:  python tools/build_scene.py
"""

from __future__ import annotations

import collections
import csv
import datetime
import json
import math
from pathlib import Path

APP = Path(__file__).resolve().parents[1]
ROOT = APP.parents[1]
DATA = ROOT / "datasets"
DERIVED = DATA / "derived"
OUT = APP / "public" / "data" / "scene.json"

DAYS = [(datetime.date(2026, 9, 12) + datetime.timedelta(days=i)).isoformat() for i in range(14)]
D0 = "2026-09-15"

# Normalizacja skladowych KIS (kalibracja 2026-08-04, notebooks/_calibrate.py).
# Wartosc dzielnika = poziom, przy ktorym skladowa osiaga 100 pkt.
# Dobrane z rozkladu faktycznych danych tak, by kulminacja (2026-09-17) przebijala
# prog 85 = zwolanie RZZK punktowo, a nie zalewala mapy czerwienia.
INC_DIV = 5.0     # zgloszen na gmine/dobe (p95 = 4, max = 8)
PWR_DIV = 1200.0  # odbiorcow bez pradu na gmine/dobe (mediana 1027, max 10 749)
EV_DIV = 250.0    # ewakuowanych na gmine/dobe (p90 = 414, max 604)
RES_DIV = 900.0   # punkty obciazenia sil i srodkow na wojewodztwo/dobe (mediana 132, max 2390)


def read_csv(name: str) -> list[dict]:
    with open(DATA / name, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def read_derived(name: str) -> list[dict]:  # zachowane dla ewentualnych porownan
    with open(DERIVED / name, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def stream(name: str):
    with open(DATA / f"{name}.jsonl", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


def r1(x: float) -> float:
    return round(x + 0.0, 1)


# ---------------------------------------------------------------------------
# Korekta wspolrzednych
# ---------------------------------------------------------------------------
#
# `generate_datasets.py` rozrzuca gminy i wodowskazy losowym odchyleniem wokol
# srodka wojewodztwa, bez sprawdzania granic. Dopoki mapa rysowala sama siatke,
# nie bylo tego widac; po naniesieniu prawdziwych granic czesc punktow ladowala
# poza krajem. Poprawiamy to wylacznie przy budowie sceny - zbiory zrodlowe,
# notatniki, Eventhouse i model semantyczny zostaja nietkniete.

RINGS_FILE = Path(__file__).resolve().parent / "poland_rings.json"

# Ile drogi w strone srodka wielokata pokonuje punkt po przyciagnieciu na
# granice - bez tego siadalby dokladnie na kresce.
INWARD = 0.06


def _fold(text: str) -> str:
    """Nazwy wojewodztw w zbiorach sa bez znakow diakrytycznych, w granicach - z."""
    import unicodedata

    text = text.replace("\u0142", "l").replace("\u0141", "L")
    stripped = unicodedata.normalize("NFD", text)
    return "".join(c for c in stripped if unicodedata.category(c) != "Mn").lower()


def load_regions() -> dict[str, list[list[list[float]]]]:
    if not RINGS_FILE.exists():
        raise SystemExit(
            f"brak {RINGS_FILE.name} - uruchom najpierw: python tools/build_poland_geo.py"
        )
    with open(RINGS_FILE, encoding="utf-8") as f:
        return {_fold(k): v for k, v in json.load(f).items()}


def in_region(lon: float, lat: float, rings: list[list[list[float]]]) -> bool:
    """Test parzystosci przeciec promienia poziomego."""
    inside = False
    for ring in rings:
        n = len(ring)
        for i in range(n):
            x1, y1 = ring[i]
            x2, y2 = ring[(i + 1) % n]
            if (y1 > lat) != (y2 > lat):
                if lon < x1 + (lat - y1) * (x2 - x1) / (y2 - y1):
                    inside = not inside
    return inside


def _km(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
    """Przyblizenie plaskie - dla odleglosci w skali wojewodztwa wystarcza."""
    return math.hypot((lon2 - lon1) * 68.5, (lat2 - lat1) * 111.2)


def snap_into(lon: float, lat: float, rings: list[list[list[float]]]) -> tuple[float, float]:
    """Najblizszy wierzcholek granicy, przesuniety w strone srodka wielokata.

    Przy ksztaltach wkleslych pojedyncze zanurzenie potrafi nie wystarczyc,
    wiec zwiekszamy je, az punkt faktycznie znajdzie sie w srodku. Wynik jest
    od razu zaokraglany do trzech miejsc, bo dokladnie taka wartosc trafi do
    sceny - sprawdzanie na pelnej precyzji przepuszczaloby punkty, ktore po
    zaokragleniu ladowaly tuz za granica.
    """
    best_vertex = None
    best_centroid = (lon, lat)
    best_d = float("inf")
    for ring in rings:
        cx = sum(p[0] for p in ring) / len(ring)
        cy = sum(p[1] for p in ring) / len(ring)
        for x, y in ring:
            d = _km(lon, lat, x, y)
            if d < best_d:
                best_d = d
                best_vertex = (x, y)
                best_centroid = (cx, cy)
    if best_vertex is None:
        return lon, lat

    vx, vy = best_vertex
    cx, cy = best_centroid
    for inward in (INWARD, 0.12, 0.25, 0.5):
        nx = round(vx + (cx - vx) * inward, 3)
        ny = round(vy + (cy - vy) * inward, 3)
        if in_region(nx, ny, rings):
            return nx, ny
    return round(cx, 3), round(cy, 3)


def correct_coordinates(
    gminas: dict[str, dict],
    gauges: dict[str, dict],
    voivs: dict[str, dict],
    g2v: dict[str, str],
) -> None:
    """Przesuwa gminy i wodowskazy do wlasnych wojewodztw."""
    regions = load_regions()
    voiv_name = {code: _fold(row["voivodeship_name"]) for code, row in voivs.items()}
    moved = {"gminy": 0, "wodowskazy": 0}

    def fix(row: dict, voiv_code: str | None) -> bool:
        rings = regions.get(voiv_name.get(voiv_code or "", ""))
        if not rings:
            return False
        # Sprawdzamy wartosc juz zaokraglona, bo taka trafi na mape. Roznica
        # miedzy pelna precyzja a trzema miejscami to ok. 100 m - przy punkcie
        # na samej granicy to decyduje, po ktorej stronie wypadnie.
        lon, lat = round(float(row["lon"]), 3), round(float(row["lat"]), 3)
        if in_region(lon, lat, rings):
            row["lon"], row["lat"] = f"{lon:.3f}", f"{lat:.3f}"
            return False
        new_lon, new_lat = snap_into(lon, lat, rings)
        row["lon"], row["lat"] = f"{new_lon:.3f}", f"{new_lat:.3f}"
        return True

    for code, row in gminas.items():
        if fix(row, g2v.get(code)):
            moved["gminy"] += 1

    # Wodowskaz jest opisany gmina, wiec bierze jej wojewodztwo.
    for row in gauges.values():
        if fix(row, g2v.get(row.get("gmina_code", ""))):
            moved["wodowskazy"] += 1

    print("korekta wspolrzednych: " + ", ".join(f"{k} {v}" for k, v in moved.items()))


def main() -> None:
    gminas = {r["gmina_code"]: r for r in read_csv("dim_gmina.csv")}
    powiats = {r["powiat_code"]: r for r in read_csv("dim_powiat.csv")}
    voivs = {r["voivodeship_code"]: r for r in read_csv("dim_voivodeship.csv")}
    gauges = {r["gauge_id"]: r for r in read_csv("dim_river_gauge.csv")}
    hazards = read_csv("dim_hazard.csv")
    spo = read_csv("dim_spo.csv")
    g2v = {g: powiats[r["powiat_code"]]["voivodeship_code"] for g, r in gminas.items()}

    correct_coordinates(gminas, gauges, voivs, g2v)

    hydro_score: dict = collections.defaultdict(dict)
    hydro_level: dict = collections.defaultdict(dict)
    alarm_flag: dict = collections.defaultdict(set)
    warn_flag: dict = collections.defaultdict(set)
    gauge_daily: dict = collections.defaultdict(dict)
    for e in stream("hydro_readings"):
        day = e["timestamp"][:10]
        g = e["gmina_code"]
        s = 100 if e["level_cm"] >= e["alarm_level_cm"] else 60 if e["level_cm"] >= e["warning_level_cm"] else 15
        hydro_score[day][g] = max(hydro_score[day].get(g, 0), s)
        hydro_level[day][g] = max(hydro_level[day].get(g, 0), e["level_cm"])
        if e["level_cm"] >= e["alarm_level_cm"]:
            alarm_flag[day].add(g)
        elif e["level_cm"] >= e["warning_level_cm"]:
            warn_flag[day].add(g)
        cur = gauge_daily[day].get(e["gauge_id"])
        if cur is None or e["level_cm"] > cur["level_cm"]:
            gauge_daily[day][e["gauge_id"]] = {
                "level_cm": e["level_cm"],
                "flow_m3s": e["flow_m3s"],
                "trend": e["trend"],
                "at": e["timestamp"][11:16],
            }

    inc_cnt: dict = collections.defaultdict(collections.Counter)
    inc_aff: dict = collections.defaultdict(collections.Counter)
    inc_p1: dict = collections.defaultdict(collections.Counter)
    inc_type_day: dict = collections.defaultdict(collections.Counter)
    inc_type_voiv: dict = collections.defaultdict(collections.Counter)
    for e in stream("incident_reports"):
        d, g = e["timestamp"][:10], e["gmina_code"]
        inc_cnt[d][g] += 1
        inc_aff[d][g] += e.get("affected_people", 0)
        if e.get("priority") == 1:
            inc_p1[d][g] += 1
        inc_type_day[d][e["event_type"]] += 1
        inc_type_voiv[(d, g2v.get(g, "--"))][e["event_type"]] += 1

    pwr_sum: dict = collections.defaultdict(collections.Counter)
    for e in stream("power_grid_events"):
        pwr_sum[e["timestamp"][:10]][e["gmina_code"]] += e["customers_offline"]

    tel_min: dict = collections.defaultdict(dict)
    for e in stream("telecom_events"):
        d, g = e["timestamp"][:10], e["gmina_code"]
        tel_min[d][g] = min(tel_min[d].get(g, 100.0), e["coverage_pct"])

    ev_max: dict = collections.defaultdict(dict)
    ev_status: dict = collections.defaultdict(dict)
    for e in stream("evacuation_status"):
        d, g = e["timestamp"][:10], e["gmina_code"]
        if e["people_count"] >= ev_max[d].get(g, 0):
            ev_max[d][g] = e["people_count"]
            ev_status[d][g] = e["status"]

    res_day: dict = collections.defaultdict(dict)
    res_load: dict = collections.defaultdict(dict)
    for e in stream("resource_deployment"):
        d, v = e["timestamp"][:10], e["voivodeship_code"]
        load = (
            e["psp_units"] * 3
            + e["wot_soldiers"] * 0.4
            + e["pumps"] * 5
            + e["generators"] * 4
            + e["helicopters"] * 25
        )
        res_load[d][v] = max(res_load[d].get(v, 0.0), load)
        prev = res_day[d].get(v)
        if prev is None or e["timestamp"] > prev["ts"]:
            res_day[d][v] = {
                "ts": e["timestamp"],
                "psp_units": e["psp_units"],
                "wot_soldiers": e["wot_soldiers"],
                "pumps": e["pumps"],
                "generators": e["generators"],
                "helicopters": e["helicopters"],
            }

    media_day: dict = collections.defaultdict(
        lambda: {"total": 0, "disinfo": 0, "reach": 0, "disinfo_reach": 0, "negative": 0}
    )
    media_topic: dict = collections.defaultdict(
        lambda: collections.defaultdict(lambda: {"count": 0, "reach": 0, "disinfo": 0})
    )
    for e in stream("media_signals"):
        d = e["timestamp"][:10]
        m = media_day[d]
        m["total"] += 1
        m["reach"] += e["reach"]
        if e["sentiment"] == "negative":
            m["negative"] += 1
        if e["disinformation_flag"]:
            m["disinfo"] += 1
            m["disinfo_reach"] += e["reach"]
        t = media_topic[d][e["topic"]]
        t["count"] += 1
        t["reach"] += e["reach"]
        t["disinfo"] += 1 if e["disinformation_flag"] else 0

    gmina_daily: list[dict] = []
    country: list[dict] = []
    voiv_daily: list[dict] = []
    active_gminas: set[str] = set()

    for day in DAYS:
        scores: list[float] = []
        byv: dict[str, list[float]] = collections.defaultdict(list)
        for g in gminas:
            c_hydro = hydro_score.get(day, {}).get(g, 0)
            c_inc = min(100.0, inc_cnt.get(day, {}).get(g, 0) / INC_DIV * 100)
            c_pwr = min(100.0, pwr_sum.get(day, {}).get(g, 0) / PWR_DIV * 100)
            c_tel = 100 - tel_min.get(day, {}).get(g, 100.0)
            c_ev = min(100.0, ev_max.get(day, {}).get(g, 0) / EV_DIV * 100)
            c_res = min(100.0, res_load.get(day, {}).get(g2v[g], 0.0) / RES_DIV * 100)
            kis = min(
                100.0,
                round(0.30 * c_hydro + 0.25 * c_inc + 0.15 * c_pwr + 0.10 * c_tel + 0.10 * c_ev + 0.10 * c_res, 1),
            )
            scores.append(kis)
            byv[g2v[g]].append(kis)
            has_data = (
                g in hydro_score.get(day, {})
                or g in inc_cnt.get(day, {})
                or g in pwr_sum.get(day, {})
                or g in tel_min.get(day, {})
                or g in ev_max.get(day, {})
            )
            if has_data:
                active_gminas.add(g)
                gmina_daily.append(
                    {
                        "d": day,
                        "g": g,
                        "kis": kis,
                        "c": [
                            r1(0.30 * c_hydro),
                            r1(0.25 * c_inc),
                            r1(0.15 * c_pwr),
                            r1(0.10 * c_tel),
                            r1(0.10 * c_ev),
                            r1(0.10 * c_res),
                        ],
                        "lvl": hydro_level.get(day, {}).get(g, 0),
                        "alarm": 1 if g in alarm_flag.get(day, set()) else (2 if g in warn_flag.get(day, set()) else 0),
                        "inc": inc_cnt.get(day, {}).get(g, 0),
                        "p1": inc_p1.get(day, {}).get(g, 0),
                        "aff": inc_aff.get(day, {}).get(g, 0),
                        "off": pwr_sum.get(day, {}).get(g, 0),
                        "cov": r1(tel_min[day][g]) if g in tel_min.get(day, {}) else None,
                        "evac": ev_max.get(day, {}).get(g, 0),
                        "evs": ev_status.get(day, {}).get(g),
                    }
                )

        res_tot: collections.Counter = collections.Counter()
        for v, r in res_day.get(day, {}).items():
            for k in ("psp_units", "wot_soldiers", "pumps", "generators", "helicopters"):
                res_tot[k] += r[k]

        md = media_day.get(day, {"total": 0, "disinfo": 0, "reach": 0, "disinfo_reach": 0, "negative": 0})
        country.append(
            {
                "d": day,
                "kis": r1(sum(scores) / len(scores)),
                "maxKis": max(scores),
                "over25": sum(s >= 25 for s in scores),
                "over45": sum(s >= 45 for s in scores),
                "over85": sum(s >= 85 for s in scores),
                "alarmGminas": len(alarm_flag.get(day, set())),
                "warnGminas": len(warn_flag.get(day, set())),
                "inc": sum(inc_cnt.get(day, {}).values()),
                "p1": sum(inc_p1.get(day, {}).values()),
                "aff": sum(inc_aff.get(day, {}).values()),
                "off": sum(pwr_sum.get(day, {}).values()),
                "evac": sum(ev_max.get(day, {}).values()),
                "minCov": r1(min(tel_min[day].values())) if tel_min.get(day) else None,
                "covBelow50": sum(1 for v in tel_min.get(day, {}).values() if v < 50),
                "media": md["total"],
                "disinfo": md["disinfo"],
                "disinfoReach": md["disinfo_reach"],
                "negative": md["negative"],
                "res": dict(res_tot),
                "topTypes": inc_type_day.get(day, collections.Counter()).most_common(6),
            }
        )

        for v in voivs:
            arr = byv.get(v, [0.0])
            vg = [g for g in gminas if g2v[g] == v]
            cov = [tel_min[day][g] for g in vg if g in tel_min.get(day, {})]
            voiv_daily.append(
                {
                    "d": day,
                    "v": v,
                    "kis": r1(sum(arr) / len(arr)),
                    "maxKis": max(arr),
                    "alarmGminas": sum(1 for g in vg if g in alarm_flag.get(day, set())),
                    "warnGminas": sum(1 for g in vg if g in warn_flag.get(day, set())),
                    "inc": sum(inc_cnt.get(day, {}).get(g, 0) for g in vg),
                    "p1": sum(inc_p1.get(day, {}).get(g, 0) for g in vg),
                    "aff": sum(inc_aff.get(day, {}).get(g, 0) for g in vg),
                    "off": sum(pwr_sum.get(day, {}).get(g, 0) for g in vg),
                    "evac": sum(ev_max.get(day, {}).get(g, 0) for g in vg),
                    "minCov": r1(min(cov)) if cov else None,
                    "res": {k: v2 for k, v2 in res_day.get(day, {}).get(v, {}).items() if k != "ts"},
                    "topTypes": inc_type_voiv.get((day, v), collections.Counter()).most_common(5),
                }
            )

    escalations = [
        {
            "ts": e["timestamp"],
            "id": e["event_id"],
            "from": e["from_level"],
            "to": e["to_level"],
            "area": e["area"],
            "hazard": e["hazard_code"],
            "spo": e["recommended_spo"],
            "reason": e["reason"],
        }
        for e in stream("escalation_events")
    ]

    # Rekomendacje eskalacji liczone tu, wg progow z notebooks/03_escalation_recommendation.py.
    # Nie czytamy datasets/derived/*.csv, bo te pliki bywaja starsze niz datasets/.
    def rec_level(kis: float) -> tuple[str, list[str]]:
        if kis >= 85:
            return "RZZK", ["SPO-1", "SPO-2", "SPO-3", "SPO-10"]
        if kis >= 65:
            return "minister wiodący", ["SPO-12", "SPO-3"]
        if kis >= 45:
            return "wojewoda", ["SPO-3", "SPO-12"]
        if kis >= 25:
            return "powiat", ["SPO-3", "SPO-12"]
        return "gmina", ["SPO-3"]

    rec_voiv = []
    for row in voiv_daily:
        if row["maxKis"] < 25:
            continue
        level, spo_codes = rec_level(row["maxKis"])
        rec_voiv.append(
            {
                "d": row["d"],
                "v": row["v"],
                "maxKis": row["maxKis"],
                "level": level,
                "spo": spo_codes,
                "why": f"Max lokalny KIS={row['maxKis']}; gminy w alarmie: {row['alarmGminas']}; "
                f"incydenty: {row['inc']}; bez zasilania: {row['off']}",
            }
        )

    rec_gmina = []
    for row in gmina_daily:
        if row["kis"] < 25:
            continue
        level, spo_codes = rec_level(row["kis"])
        rec_gmina.append(
            {
                "d": row["d"],
                "g": row["g"],
                "v": g2v[row["g"]],
                "kis": row["kis"],
                "level": level,
                "spo": spo_codes,
            }
        )

    gauge_rows = []
    for day in DAYS:
        for gid, val in gauge_daily.get(day, {}).items():
            gauge_rows.append(
                {
                    "d": day,
                    "id": gid,
                    "lvl": val["level_cm"],
                    "flow": val["flow_m3s"],
                    "trend": val["trend"],
                    "at": val["at"],
                }
            )

    scene = {
        "meta": {
            "generatedAt": datetime.datetime.now().isoformat(timespec="seconds"),
            "days": DAYS,
            "d0": D0,
            "source": "datasets/ (deterministyczna scena powodziowa 2026-09-12..25)",
            "kisFormula": "0,30*hydro + 0,25*incydenty + 0,15*energia + 0,10*telekom + 0,10*ewakuacja + 0,10*zasoby",
            "kisComponents": ["hydrologia", "incydenty", "energia", "telekom", "ewakuacja", "siły i środki"],
        },
        "voivodeships": [
            {
                "code": r["voivodeship_code"],
                "name": r["voivodeship_name"],
                "pop": int(r["population"]),
                "seat": r["wczk_seat"],
                "lat": float(r["lat"]),
                "lon": float(r["lon"]),
            }
            for r in voivs.values()
        ],
        "gminas": [
            {
                "code": g,
                "name": gminas[g]["gmina_name"],
                "v": g2v[g],
                "powiat": powiats[gminas[g]["powiat_code"]]["powiat_name"],
                "pop": int(gminas[g]["population"]),
                "lat": float(gminas[g]["lat"]),
                "lon": float(gminas[g]["lon"]),
            }
            for g in sorted(active_gminas)
        ],
        "gauges": [
            {
                "id": r["gauge_id"],
                "name": r["gauge_name"],
                "river": r["river"],
                "g": r["gmina_code"],
                "warn": int(r["warning_level_cm"]),
                "alarm": int(r["alarm_level_cm"]),
                "lat": float(r["lat"]),
                "lon": float(r["lon"]),
                "delayH": float(r["wave_delay_h"]) if r["wave_delay_h"] else 0.0,
            }
            for r in gauges.values()
            if r["gmina_code"] in active_gminas
        ],
        "hazards": [
            {
                "code": r["hazard_code"],
                "name": r["hazard_name"],
                "lead": r["lead_minister"],
                "coop": r["cooperating_ministers"],
            }
            for r in hazards
        ],
        "spo": [{"code": r["spo_code"], "name": r["spo_name"]} for r in spo],
        "country": country,
        "voivDaily": voiv_daily,
        "gminaDaily": gmina_daily,
        "gaugeDaily": gauge_rows,
        "escalations": escalations,
        "recVoiv": rec_voiv,
        "recGmina": rec_gmina,
        "mediaTopics": [
            {"d": d, "topic": t, "count": v["count"], "reach": v["reach"], "disinfo": v["disinfo"]}
            for d, topics in media_topic.items()
            for t, v in topics.items()
        ],
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(scene, f, ensure_ascii=False, separators=(",", ":"))
    print(f"scene.json: {OUT.stat().st_size / 1024:.1f} KB")
    print(f"gminy aktywne: {len(scene['gminas'])}, gminaDaily: {len(gmina_daily)}, voivDaily: {len(voiv_daily)}")
    peak = max(country, key=lambda c: c["off"])
    print(f"szczyt energii: {peak['d']} = {peak['off']} odbiorcow")
    print(f"gminy alarmowe (unikalne): {len(set().union(*alarm_flag.values()))}")
    print(f"dezinformacja lacznie: {sum(c['disinfo'] for c in country)}")
    print(f"max ewakuowanych w dniu: {max(c['evac'] for c in country)}")
    print(f"max lokalny KIS: {max(c['maxKis'] for c in country)}")


if __name__ == "__main__":
    main()

