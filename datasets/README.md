# 📦 Datasety COP-24

> ⚠️ Dane są w 100% syntetyczne, wygenerowane proceduralnie z `seed=42`. Nie są danymi operacyjnymi żadnej instytucji, nie zawierają danych osobowych i służą wyłącznie demonstracji Microsoft Fabric Real-Time Intelligence.

## Zakres scenariusza

Oś czasu obejmuje D-3…D+10 wokół D0 = 2026-09-15 12:00 +02:00. Główne zagrożenie to Z02 Powódź, a współwystępują Z07 Energetyka, Z12 Telekomunikacja i Z20 Dezinformacja. Dane są spójne z osią fali Nysa Kłodzka → Odra oraz eskalacją gmina→powiat→wojewoda→minister→RZZK.

## Spis plików źródłowych

| Plik | Rekordy | Zakres czasowy | Opis |
|---|---:|---|---|
| `dim_gmina.csv` | 2477 | — | Gminy syntetyczne powiązane z powiatem i typem administracyjnym. |
| `dim_hazard.csv` | 20 | — | Kanoniczne 20 zagrożeń KPZK Z01–Z20. |
| `dim_institution.csv` | 422 | — | Instytucje raportujące na poziomie krajowym, wojewódzkim i powiatowym. |
| `dim_powiat.csv` | 380 | — | Powiaty syntetyczne powiązane z województwem. |
| `dim_river_gauge.csv` | 120 | — | Wodowskazy z progami ostrzegawczymi/alarmowymi i opóźnieniem fali. |
| `dim_spo.csv` | 16 | — | 16 Standardowych Procedur Operacyjnych. |
| `dim_voivodeship.csv` | 16 | — | Województwa z kodem TERYT, populacją i siedzibą WCZK. |
| `escalation_events.jsonl` | 5 | 2026-09-15T04:00:00+02:00 — 2026-09-15T20:00:00+02:00 | Zdarzenia eskalacji poziomu reagowania w D0. |
| `evacuation_status.jsonl` | 321 | 2026-09-14T18:00:00+02:00 — 2026-09-20T23:00:00+02:00 | Etapy ewakuacji per gmina: planned/in_progress/completed. |
| `hydro_readings.jsonl` | 449400 | 2026-09-12T12:00:00+02:00 — 2026-09-25T12:00:00+02:00 | Odczyty wodowskazów co 5 minut; największy strumień telemetrii. |
| `incident_reports.jsonl` | 4943 | 2026-09-12T12:01:00+02:00 — 2026-09-25T12:11:00+02:00 | Zgłoszenia 112/PSP z typem, priorytetem i liczbą osób objętych. |
| `media_signals.jsonl` | 3028 | 2026-09-12T12:13:00+02:00 — 2026-09-25T12:21:00+02:00 | Sygnały medialne i społecznościowe, w tym Z20 Dezinformacja. |
| `power_grid_events.jsonl` | 541 | 2026-09-12T18:34:00+02:00 — 2026-09-25T12:47:00+02:00 | Zdarzenia energetyczne, stacje i odbiorcy bez prądu. |
| `resource_deployment.jsonl` | 432 | 2026-09-12T12:00:00+02:00 — 2026-09-25T12:00:00+02:00 | Siły i środki per województwo co 12 godzin. |
| `telecom_events.jsonl` | 351 | 2026-09-12T18:35:00+02:00 — 2026-09-25T12:42:00+02:00 | Zdarzenia telekomunikacyjne, operator, pokrycie i stacje bazowe. |
| `weather_observations.jsonl` | 118940 | 2026-09-12T12:00:00+02:00 — 2026-09-25T12:00:00+02:00 | Obserwacje pogody per powiat co godzinę. |

## Pliki derived/

Pliki w `datasets/derived/` są wynikami uruchomienia notebooków i skryptów kontrolnych. Nie zastępują danych źródłowych; przyspieszają demo, Data Agenta i dokumentację.

| Plik | Rekordy | Opis |
|---|---:|---|
| `derived/demo_metrics.json` | 248 | metryki narracyjne i kontrolne używane w dokumentacji |
| `derived/escalation_recommendations.csv` | 194 | rekomendacje eskalacji per gmina/dzień |
| `derived/escalation_recommendations_voivodeship.csv` | 34 | rekomendacje eskalacji per województwo/dzień |
| `derived/kis_daily_country.csv` | 14 | dzienny KIS krajowy i liczba gmin powyżej progów |
| `derived/kis_daily_voivodeship.csv` | 224 | dzienny KIS wojewódzki i lokalne maksimum |

## Jak używać danych

1. Do ponownego wygenerowania źródeł uruchom `python generate_datasets.py`.
2. Do testu replay użyj `python simulate_realtime.py --stream hydro_readings --dry-run`.
3. Do odtworzenia warstwy derived uruchom `python notebooks_situation_index.py` oraz `python notebooks_escalation_recommendation.py`.
4. Do Fabric wgrywaj CSV jako wymiary Lakehouse, a JSONL jako strumienie/Eventhouse albo jako pliki testowe.

## Uwagi jakościowe

CSV ma separator `,`, kodowanie UTF-8 i nagłówki. JSONL ma jeden obiekt JSON na linię. Daty są ISO-8601 z offsetem `+02:00`. Kody TERYT są syntetyczne, ale zachowują strukturę województwo/powiat/gmina. Nazwy techniczne kolumn są angielskie i bez polskich znaków.

## ⚠️ Pliki danych spoza repozytorium

Najwieksze pliki strumieniowe nie sa wersjonowane w Git (limity GitHub, czas klonowania).
Sa **w pelni odtwarzalne** — generator uzywa `seed=42`:

```powershell
python generate_datasets.py
```

Pliki wylaczone z repozytorium:
- `hydro_readings.jsonl` (~95 MB, 449 400 rekordow)

