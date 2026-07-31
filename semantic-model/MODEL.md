# ⭐ Model semantyczny COP-24

Model jest klasyczną gwiazdą z hierarchią TERYT i kilkoma faktami strumieniowymi. Celem jest umożliwienie drill-down województwo→powiat→gmina oraz spójnych miar dla dashboardu i raportu Power BI.

## Tabele wymiarów

`dim_voivodeship` (1) → `dim_powiat` (N) po `voivodeship_code`; `dim_powiat` (1) → `dim_gmina` (N) po `powiat_code`. `dim_hazard` łączy się z faktami po `hazard_code`; `dim_spo` po `spo_code` albo przez tabelę rekomendacji. `dim_river_gauge` łączy wodowskazy z gminami.

## Fakty

`hydro_readings` ma ziarno `timestamp,gauge_id`; `incident_reports` ma ziarno `incident_id`; `power_grid_events`, `telecom_events`, `evacuation_status`, `resource_deployment`, `media_signals` i `escalation_events` są osobnymi faktami zdarzeń. `kis_gmina`, `kis_powiat`, `kis_voivodeship`, `kis_country` to fakty wynikowe z notebooków.

## Relacje i kierunki filtrowania

Relacje od wymiarów do faktów są jednokierunkowe. Unikaj many-to-many między faktami; korelacje licz w KQL albo w tabelach derived. Kardynalności: `dim_gmina` 1→N `incident_reports`, `power_grid_events`, `telecom_events`, `evacuation_status`; `dim_river_gauge` 1→N `hydro_readings`; `dim_voivodeship` 1→N `resource_deployment`.

## Tabela dat

Utwórz `Date` z rozdzielczością co najmniej godzinową dla raportu oraz minutową, jeśli Power BI ma analizować okna 15-minutowe. Kolumny: `DateTime`, `Date`, `Hour`, `DayOffset`, `DemoPhase`. Relacja do faktów po `timestamp`, najlepiej przez widoki agregujące do godziny/dnia dla wydajności.

## Zasady modelowania

Nie mieszaj danych raw i decyzyjnych na jednym ekranie bez opisu. Miary krajowe powinny agregować po geografii, a nie sumować indeksów bez wag populacyjnych, jeśli raport ma charakter produkcyjny. W demo używamy średniej prostej dla przejrzystości, co trzeba jasno powiedzieć decydentowi.

## Widoki agregujące

Dla wydajności zaleca się utworzyć widoki lub tabele agregujące: `hydro_latest`, `incidents_agg_15min`, `power_hourly`, `telecom_latest`, `media_disinfo_15min`, `kis_daily_country` i `kis_daily_voivodeship`. Raport Power BI powinien używać agregatów tam, gdzie celem jest decyzja, a nie analiza pojedynczego zdarzenia.

## Bezpieczeństwo modelu

W demo nie ma danych osobowych, ale w produkcji należy zastosować RLS po województwie dla roli wojewody i ograniczenia kolumn dla danych wrażliwych. RCB i uprawnione ministerstwa mogą widzieć kraj, ale eksport powinien być kontrolowany. Decyzje i logi audytowe muszą być append-only.

## Nazewnictwo

Nazwy tabel i kolumn pozostają angielskie oraz bez polskich znaków, aby były bezpieczne technicznie w KQL, Spark i DAX. Nazwy miar i etykiety raportu mogą być po polsku. Słownik biznesowy powinien mapować `gmina_code`, `powiat_code`, `voivodeship_code` na język administracyjny TERYT.

## Wdrożenie

Model i raport wdraża skrypt:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\deploy\create_semantic_model.ps1 `
  -WorkspaceName 'OL-ZK-Demo-COP24'
```

Skrypt pobiera tokeny przez `az account get-access-token`, tworzy lub aktualizuje model `OL_COP24_SemanticModel` oraz wywołuje `deploy\create_report.ps1` dla raportu `OL_COP24_Raport`. Definicja modelu jest generowana w TMDL do `semantic-model\generated\` i wdrażana przez Fabric REST API `semanticModels` / `updateDefinition`. W modelu użyto partycji `mode: directLake` oraz źródła `DirectLakeSqlEndpoint` przez SQL endpoint Lakehouse.

Raport jest wdrażany idempotentnie przez Fabric REST API `items/{reportId}/updateDefinition` w folderowym formacie PBIR. Pełna definicja lokalna znajduje się w `semantic-model\report\`: pliki PBIR, pięć stron, osobne `visual.json`, zarejestrowany motyw `COP24-CommandCenter-c0242026.json` oraz manifest i wyniki walidacji DAX.

Raport `OL_COP24_Raport` ma pięć stron:

- `Obraz kraju` — sytuacja krajowa, mapa ryzyka gmin, trend incydentów i drabina eskalacji.
- `Hydrologia i fala` — mapa wodowskazów, małe multiplikatory rzek, wykres kombi przepływ–poziom i macierz progów.
- `Infrastruktura krytyczna` — korelacja hydro→energia→telco, trendy awarii i macierz kaskady.
- `Siły, środki i ewakuacja` — ewakuacja, skumulowany bilans zasobów, mobilizacja PSP/WOT i macierz województw.
- `Eskalacja, SPO i dezinformacja` — rekomendacje RZZK, procedury SPO, kanały i zasięg Z20 oraz uzasadnienia decyzji.

Po wdrożeniu `create_report.ps1`:

1. wykonuje osobne zapytanie DAX przez `executeQueries` dla każdej wizualizacji,
2. porównuje 24 kluczowe miary z wartościami kontrolnymi scenariusza,
3. pobiera `getDefinition?format=PBIR`,
4. sprawdza liczbę stron i plików `visual.json`,
5. zapisuje wyniki w `semantic-model\report\validation\results.json`.

Szczegółowy katalog stron i wizualizacji znajduje się w `semantic-model\RAPORT.md`.
