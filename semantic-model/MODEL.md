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

Skrypt pobiera tokeny przez `az account get-access-token`, tworzy lub aktualizuje model `OL_COP24_SemanticModel` oraz raport `OL_COP24_Raport`. Definicja modelu jest generowana w TMDL do `semantic-model\generated\` i wdrażana przez Fabric REST API `semanticModels` / `updateDefinition`. W modelu użyto partycji `mode: directLake` oraz źródła `DirectLakeSqlEndpoint` przez SQL endpoint Lakehouse; wcześniejsze próby `AzureStorage.DataLake` dla Direct Lake on OneLake zwracały brak dostępu lub brak tabel przy weryfikacji DAX.

Raport jest wdrażany idempotentnie przez Fabric REST API `items/{reportId}/updateDefinition` w folderowym formacie PBIR. Definicja lokalna jest zapisywana w `semantic-model\report\` jako `definition.pbir`, `definition\report.json`, `definition\version.json`, `definition\pages\pages.json`, pliki `page.json` oraz osobne pliki `visual.json` dla każdej wizualizacji. Połączenie z modelem jest zapisane w `definition.pbir` jako `datasetReference.byConnection` z `semanticmodelid`.

Raport `OL_COP24_Raport` ma cztery strony:

- `Obraz kraju`: karty KPI alarmu hydro, osób objętych zgłoszeniami, ewakuacji i odbiorców bez prądu; KIS wg województw; incydenty w czasie; mapa gmin wg KIS; top gminy wg KIS.
- `Województwo i gminy`: slicer województwa, tabela gmin z KIS i skutkami, top 15 gmin wg KIS, poziomy wody w czasie oraz karta alarmu hydro.
- `Infrastruktura krytyczna`: odbiorcy bez prądu w czasie, gminy z ograniczoną łącznością, awarie energii wg gmin oraz tabela korelacji energii i łączności.
- `Eskalacja i SPO`: tabela rekomendacji eskalacji, uruchomione SPO, zaangażowane siły i środki, karty rekomendacji RZZK i maksymalnego KIS lokalnego.

Po wdrożeniu skrypt wykonuje `getDefinition` i zapytanie DAX przez Power BI REST API:

```dax
EVALUATE ROW("n", COUNTROWS('dim_gmina'))
```

Oczekiwany wynik kontrolny dla danych demo to `2477`. Dodatkowo po zmianach raportu należy pobrać definicję przez `getDefinition?format=PBIR` i sprawdzić obecność części `definition/pages/*/visuals/*/visual.json`, a dla wizualizacji danych wykonać równoważne zapytania DAX przez `executeQueries`.
