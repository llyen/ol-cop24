# 🚀 Stan wdrożenia COP-24 na Microsoft Fabric

Dokument opisuje **rzeczywisty, zweryfikowany** stan środowiska demonstracyjnego oraz kolejność
kroków, którymi zostało ono zbudowane. Służy do odtworzenia wdrożenia i do rozliczenia prac.

## 1. Środowisko

| Element | Wartość |
|---|---|
| Workspace | `OL-ZK-Demo-COP24` |
| Workspace ID | `8ea0556f-7368-4b36-ad84-adf995e19a80` |
| Pojemność | `fcdemo` (F8, Active) |
| Region klastra | West Europe |
| Tenant | `7ada8cf4-c4be-488f-a844-6d37ee64849e` |

## 2. Utworzone elementy

| Element | Typ | ID |
|---|---|---|
| `OL_COP24_Lakehouse` | Lakehouse | `2d840a79-be01-4f82-be45-d4d45e0992ea` |
| `OL_COP24_Eventhouse` | Eventhouse | `8be13fdf-ad4c-48d7-805a-c02cf669386b` |
| `OL_COP24_Eventhouse` | KQL Database | `c3c2fbc2-7fa9-4b70-b82d-c76f79640b37` |
| `OL_COP24_Eventstream` | Eventstream | `c964c29e-bdd7-46b6-b59f-89b3a49d3338` |
| `01_load_dimensions` | Notebook | `5956cccf-742b-44e9-901a-38da92003797` |
| `01b_load_streams` | Notebook | — |
| `02_situation_index` | Notebook | `481a0c32-8684-46b1-96c5-bc694eb8de8a` |
| `03_escalation_recommendation` | Notebook | `ad666d46-7097-470f-9ed7-0a277b83002a` |
| `OL_COP24_SemanticModel` | Semantic Model (Direct Lake) | `669a6a2b-0115-4eeb-8f63-a6e1027133b0` |
| `OL_COP24_Raport` | Raport Power BI | `a0449186-59df-49f4-a151-9ceceb06726e` |
| `agent_cop24` | Data Agent | `7733697a-5231-4b8c-a9ac-bd5a6ce62adc` |

Cluster URI Eventhouse: `https://trd-tmsdqpz0s6cg6aewj9.z3.kusto.fabric.microsoft.com`

## 3. Kolejność wdrożenia

```powershell
# 1. Lakehouse + Eventhouse + tabele KQL + mapowania + widoki zmaterializowane
.\deploy\deploy_fabric.ps1 -Step items
.\deploy\deploy_fabric.ps1 -Step kql

# 2. Wysyłka danych do OneLake (CSV -> Files/datasets, JSONL -> Files/streams)
.\deploy\deploy_fabric.ps1 -Step upload

# 3. Ingest strumieni do Eventhouse + weryfikacja liczności
.\deploy\deploy_fabric.ps1 -Step ingest
.\deploy\deploy_fabric.ps1 -Step verify

# 4. Import notatnikow
.\deploy\import_notebooks.ps1

# 5. Uruchomienie notatnikow w kolejnosci 01 -> 01b -> 02 -> 03 (UI albo REST API)
```

## 4. Zweryfikowane liczności w Eventhouse

| Tabela | Wiersze |
|---|---|
| `hydro_readings` | 449 400 |
| `weather_observations` | 118 940 |
| `incident_reports` | 4 943 |
| `media_signals` | 3 028 |
| `power_grid_events` | 541 |
| `resource_deployment` | 432 |
| `telecom_events` | 351 |
| `evacuation_status` | 321 |
| `escalation_events` | 5 |

Zakres czasu: `2026-09-12` … `2026-09-25`.

## 5. Tabele Delta w Lakehouse (21)

Wymiary (notatnik `01`): `dim_voivodeship`, `dim_powiat`, `dim_gmina`, `dim_hazard`,
`dim_institution`, `dim_spo`, `dim_river_gauge`.

Strumienie (notatnik `01b`): `hydro_readings`, `weather_observations`, `incident_reports`,
`power_grid_events`, `telecom_events`, `evacuation_status`, `resource_deployment`,
`media_signals`, `escalation_events`.

Wyniki modeli (notatniki `02`, `03`): `kis_gmina`, `kis_powiat`, `kis_voivodeship`,
`kis_country`, `escalation_recommendations`.

## 6. Ścieżka real-time

```
simulate_realtime.py  ──►  Eventstream (custom endpoint)  ──►  Eventhouse: hydro_readings_rt
```

Uruchomienie:

```powershell
# Pobranie connection stringu custom endpointu do pliku .env (nie trafia do repozytorium)
$ws  = '8ea0556f-7368-4b36-ad84-adf995e19a80'
$es  = 'c964c29e-bdd7-46b6-b59f-89b3a49d3338'
$t   = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
$topo = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ws/eventstreams/$es/topology" -Headers @{Authorization="Bearer $t"}
$src  = $topo.sources | Where-Object type -eq 'CustomEndpoint'
$conn = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ws/eventstreams/$es/sources/$($src.id)/connection" -Headers @{Authorization="Bearer $t"}
Set-Content .env @("EVENTHUB_CONNECTION_STRING=$($conn.accessKeys.primaryConnectionString)", "EVENTHUB_NAME=$($conn.eventHubName)") -Encoding utf8

# Odtwarzanie fali wezbraniowej
python simulate_realtime.py --stream hydro_readings --from 2026-09-16T00:00:00 --to 2026-09-18T00:00:00
```

Weryfikacja w Eventhouse: `hydro_readings_rt | summarize count(), max(timestamp)`.
Test kontrolny wdrożenia: 3 000 zdarzeń pojawiło się w tabeli w ok. 60 sekund od wysyłki.

## 7. Napotkane problemy i rozwiązania

| Problem | Rozwiązanie |
|---|---|
| `Cannot convert 'System.String[]' to 'System.Uri'` przy odczycie nagłówka `Location` | W PowerShell 7 nagłówek jest tablicą — `$r.Headers.Location \| Select-Object -First 1` |
| Fabric odrzuca definicję notatnika zawierającą `kernelspec` | W `.ipynb` zostawiamy wyłącznie `language_info` oraz `metadata.dependencies.lakehouse` |
| `InvalidNotebookContent`: `cells[].source` nie może być pojedynczym łańcuchem | `source` musi być listą linii zakończonych `\n` |
| `InvalidFlushPosition` przy wysyłce plików > 8 MB do OneLake | Fragment bufora kopiować przez `[Array]::Copy` do nowej tablicy `byte[]`, nie przez `$buf[0..n]` |
| Mirroring KQL → OneLake nie eksportował istniejących danych | Polityka wymaga jawnego `Backfill=true`; efektywna latencja i tak wynosi 180 min, dlatego tabele Delta ładuje notatnik `01b` bezpośrednio z `Files/streams/` |
| Destynacja Eventstream → Eventhouse: `ESComponentCreationFailure` (błąd podpisu tokenu Event Hub) | Błąd przejściowy po stronie usługi — ponowne wdrożenie definicji z trybem `ProcessedIngestion` kończy się statusem `Running` |
| Symulator: `can't compare offset-naive and offset-aware datetimes` | Znaczniki czasu bez strefy interpretowane jako UTC w `parse_ts` |

## 8. Kroki pozostające do wykonania w interfejsie

1. **Real-Time Dashboard** — `deploy\create_dashboard.ps1` oraz `dashboard\RTI_DASHBOARD.md`.
2. **Activator** — reguły z `activator\RULES.md` (progi alarmowe, eskalacja, dezinformacja).
3. **Model semantyczny i raport** — `semantic-model\MODEL.md`, `semantic-model\MEASURES.md`.
4. ~~**Data Agent**~~ — **wdrożony** skryptem `deploy\create_data_agent.py` (element `agent_cop24`).
   Instrukcja systemowa jest składana z `ai\DATA_AGENT.md`, więc zmiana specyfikacji wymaga
   ponownego uruchomienia skryptu. Podpięte źródła: Lakehouse (21 tabel), Eventhouse (16 tabel),
   model semantyczny (20 tabel). W interfejsie pozostaje jedynie **publikacja** agenta —
   przejście z wersji roboczej do produkcyjnej; API tego nie udostępnia.
5. ~~**Fabric App / Rayfin**~~ — **wdrożone 2026-08-04**, patrz sekcja 9.

## 9. Fabric App — „Pulpit RZZK" (wdrożone)

| Element | Wartość |
|---|---|
| Katalog | `fabric-app\pulpit-rzzk` |
| URL aplikacji | https://key-horn-c1ee0f1637-westeurope.webapp.fabricapps.net |
| Rayfin Item ID | `8dd3360a-512e-46a8-8bd3-8eab3be64d73` |
| Ekrany | Obraz sytuacji, Województwo, Rekomendacje, Rejestr decyzji, Zwołanie RZZK |
| Zapis (SQL) | `DecisionLog`, `SpoActionLog`, `BriefRequest`, `NotificationLog` |
| Odczyt | statyczna scena `public/data/scene.json` (839 KB, 14 dób) z `tools/build_scene.py` |
| Mapa | granice 16 województw, przybliżanie i przesuwanie (kółko, szczypanie, przeciągnięcie, dwuklik, przyciski, klawiatura) |
| Testy | 37 (vitest), lint bez błędów, build OK |

### Mapa i korekta współrzędnych

Mapa rysuje kontury województw z `src/data/poland.ts` — plik powstaje z granic GUS
(`ppatrzyk/polska-geojson`, licencja MIT) przez `tools/build_poland_geo.py`, który
upraszcza geometrię z 77 tys. do 7 tys. wierzchołków i rzutuje ją na tę samą siatkę,
na którą trafiają punkty. Dzięki temu obie warstwy zawsze się pokrywają. Znaczniki
są dzielone przez współczynnik przybliżenia, więc na ekranie zachowują stałą wielkość.

Naniesienie prawdziwych granic ujawniło defekt danych: `generate_datasets.py`
rozrzuca punkty losowym odchyleniem wokół środka województwa, bez sprawdzania
granic — 69 gmin i 13 wodowskazów leżało poza Polską. `tools/build_scene.py`
przyciąga takie punkty do własnego województwa **wyłącznie w warstwie prezentacji**.
Zbiory źródłowe, `derived/`, notatniki, Eventhouse i model semantyczny zostają
nietknięte, więc żaden wskaźnik się nie zmienia. Wodowskaz dziedziczy województwo
po swojej gminie. Pięć testów w `src/__tests__/geography.test.ts` pilnuje, że
każdy punkt leży we właściwym województwie — czytają kontur z `poland.ts`, czyli
dokładnie z tego, co rysuje aplikacja.

**Dlaczego nie Azure Maps.** Rozważone i odrzucone. Aplikacje Fabric App nie mają
nagłówka CSP, więc samo SDK by się załadowało, ale Rayfin to wyłącznie warstwa
Data API Builder — nie ma funkcji serwerowej, w której można by brokerować token.
Zostawałby klucz subskrypcji w paczce przeglądarki, a kluczy Azure Maps nie da się
ograniczyć do domeny. Wrócić do tematu tylko jeśli pojawi się miejsce na kod
serwerowy.

Dokumentacja aplikacji, reguły uprawnień, tabela napotkanych problemów oraz uwaga
o rozbieżności liczb w `RAYFIN_PROMPT.md`/`APP_SPEC.md`: `fabric-app\pulpit-rzzk\README.md`.
