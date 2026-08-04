# 🚨 Reguły Data Activator / Reflex

> Reguły są demonstracyjne. W produkcji progi zatwierdza właściciel procesu i minister/wojewoda zgodnie z procedurami.

## 1. Stan alarmowy wodowskazu
Cel: natychmiast uruchomić obieg informacji. Źródło: `hydro_readings`. KQL: `hydro_readings | where level_cm >= alarm_level_cm`. Próg: jeden odczyt, bo przekroczenie stanu alarmowego jest zdarzeniem formalnym. Odbiorca: WCZK, PCZK, RCB. Treść: „Wodowskaz {gauge_id} przekroczył alarm: {level_cm} cm”. Akcja: SPO-12 i SPO-3.

## 2. Gwałtowny przyrost poziomu
Cel: wykryć dynamikę zanim pojawi się szczyt. KQL: `hydro_readings | order by gauge_id,timestamp | extend delta=level_cm-prev(level_cm) | where delta > 20`. Próg 20 cm/30 min jest konserwatywny w demie. Odbiorca: IMGW/Wody Polskie/RCB. Akcja: weryfikacja prognozy i komunikat.

## 3. Zgłoszenia 112/PSP w gminie
Cel: powiązać zjawisko z wpływem na ludność. KQL: `incident_reports | summarize c=count() by bin(timestamp,15m), gmina_code | where c > 25`. Próg 25 oznacza przeciążenie lokalne. W danych peak 15-min wynosi 12, więc w demo można obniżyć próg testowy. Akcja: SPO-3, SPO-12.

## 4. Odbiorcy bez prądu
Cel: aktywować Z07 i IK. KQL: `power_grid_events | summarize customers=sum(customers_offline) by bin(timestamp,1h), gmina_code | where customers > 5000`. Próg: 5000 odbiorców to skala istotna społecznie. W danych szczyt godzinowy wynosi 14 168 odbiorców, a dobowy 139 539. Odbiorca: PSE/OSD, wojewoda, RCB. Akcja: SPO-10.

## 5. Brak łączności
Cel: wykryć utratę kanałów alarmowania. KQL: `telecom_events | where coverage_pct < 40 or base_stations_down >= 5`. Próg: poniżej 40% oznacza problem z dotarciem do ludności. Minimalne pokrycie w danych: 22.6%. Akcja: SPO-10 i SPO-3.

## 6. Dezinformacja Z20
Cel: uruchomić komunikację społeczną. KQL: `media_signals | where disinformation_flag == true and reach > 50000`. W danych jest 335 sygnałów o łącznym zasięgu 37 798 399. Odbiorca: CIR, NASK, RCB. Akcja: sprostowanie i SPO-3.

## 7. Rekomendacja RZZK
Cel: formalnie podnieść temat na poziom krajowy. KQL: `escalation_recommendations | where recommended_level == 'RZZK'`. Próg: KIS ≥85 albo zaangażowanie kilku ministrów. Akcja: SPO-1, SPO-2, SPO-3, SPO-10.

## Format powiadomienia

Każdy alert ma zawierać: tytuł, poziom, obszar TERYT, timestamp, warunek, wartość progu, wartość bieżącą, rekomendowaną SPO, właściciela i link do dashboardu. Przykład: „ALARM HYDRO — WG-001, 493 cm przy progu 340 cm, rekomendacja SPO-12/SPO-3, sprawdź Pulpit RZZK”.

## Priorytety i deduplikacja

Alerty hydrologiczne deduplikuj po `gauge_id` i godzinie. Alerty energetyczne po `gmina_code` i oknie 1h. Alerty dezinformacji po `topic` i kanale. Jeżeli jednocześnie występuje alarm hydro, energia >5000 i telco <40%, podnieś priorytet na `critical` i dołącz rekomendację eskalacji do RZZK.

## Human-in-the-loop

Activator nie podejmuje decyzji administracyjnej. Powiadomienie proponuje akcję, ale oficer dyżurny albo dyrektor zatwierdza wpis w Pulpicie RZZK. Każde potwierdzenie tworzy ślad w `decision_log` lub `spo_action_log`. Brak reakcji w czasie SLA powinien eskalować do kolejnego odbiorcy.

## Testy reguł przed pokazem

Przed demo wykonaj test techniczny każdej reguły na ograniczonym zakresie czasu. Dla reguły hydro użyj przedziału wokół 2026-09-15T10:05:00+02:00. Dla energii użyj godziny 2026-09-17T08:00. Dla dezinformacji użyj D0…D+3. Jeżeli próg demonstracyjny nie wyzwala alertu z powodu ograniczonego okna, obniż go tylko w środowisku demo i zanotuj to w komentarzu reguły.

## Zarządzanie hałasem alertowym

Reguły powinny mieć mechanizm „cooldown”, aby nie wysyłać tego samego alertu co pięć minut. Proponowane wartości: hydro 60 minut, energia 60 minut, telco 120 minut, dezinformacja 180 minut, RZZK bez powtórzeń po zatwierdzeniu decyzji. Alert zamknięty ręcznie nie powinien wrócić, jeśli nie pojawi się nowy wzrost wartości lub nowy obszar.

## Wdrożenie

Stan na 2026-07-31: element Fabric Activator/Reflex **OL_COP24_Activator** został utworzony w workspace **OL-ZK-Demo-COP24** (`dde1f39b-fe6c-4adb-8efe-db708cdb1bdf`). REST API Fabric pozwolił utworzyć element i zapisać w `ReflexEntities.json` źródło `eventstreamSource-v1` wskazujące na **OL_COP24_Eventstream** (`c964c29e-bdd7-46b6-b59f-89b3a49d3338`). Próby wgrania pełnych reguł `timeSeriesView-v1` przez `updateDefinition` zakończyły się błędami walidacji definicji, więc działający mechanizm demo jest wdrożony po stronie Eventhouse jako funkcje KQL.

### Skrypt automatyczny

Uruchomienie:

```powershell
cd C:\repos\OchronaLudnosci\ol-cop24
.\deploy\create_activator.ps1 -WorkspaceName OL-ZK-Demo-COP24
```

Skrypt:

1. pobiera tokeny przez Azure CLI dla Fabric REST i Kusto,
2. wyszukuje albo tworzy Activator `OL_COP24_Activator`,
3. aktualizuje definicję Activatora o źródło Eventstream,
4. tworzy/aktualizuje funkcje KQL w folderze `Activator/COP24`,
5. wykonuje zapytania weryfikacyjne i wypisuje liczbę trafień oraz próbkę rekordu.

### Funkcje KQL działające jako reguły

| Reguła | Funkcja KQL | Warunek wdrożony | Trafienia | Zakres/obszary | Pierwsze trafienie | Przykład |
|---|---|---:|---:|---|---|---|
| Stan alarmowy wodowskazu | `alert_hydro_alarm()` | `level_cm >= alarm_level_cm` | 3726 | 10 gmin, 10 wodowskazów | 2026-09-14 14:55 UTC | `WG-001`, 345 cm przy progu 340 cm |
| Gwałtowny przyrost poziomu | `alert_hydro_rapid_rise()` | poziom `>=` stanu ostrzegawczego i przyrost `>= 12 cm/h` (średnia godzinowa) | 77 | 10 gmin, 10 wodowskazów, rzeka Nysa Kłodzka | 2026-09-14 13:00 UTC | `WG-001`, 330,2 cm, wzrost +18,5 cm/h |
| Skok zgłoszeń 112/PSP | `alert_incident_spike()` | próg demo `>2` zgłoszenia/gmina/15 min; próg produkcyjny z zasad: `>25` | 4 | 4 gminy | 2026-09-16 00:15 UTC | gmina `0202003`, 3 zgłoszenia/15 min |
| Odbiorcy bez prądu | `alert_power_outage()` | suma `customers_offline > 5000`/gmina/1h | 94 | 41 gmin | 2026-09-12 19:00 UTC | gmina `1601006`, 6452 odbiorców |
| Brak/spadek łączności | `alert_telco_coverage_drop()` | `coverage_pct < 40` albo `base_stations_down >= 5` | 221 | 102 gminy | 2026-09-12 18:44 UTC | gmina `1602008`, coverage 39,2% |
| Dezinformacja Z20 | `alert_disinformation_z20()` | `disinformation_flag == true and reach > 50000` | 284 | 6 tematów, 249 okien deduplikacji | 2026-09-12 13:43 UTC | `braki paliwa/telegram`, zasięg 177229 |
| Eskalacja RZZK | `alert_escalation_rzzk()` | `to_level == RZZK` lub poziom ministerialny | 2 | obszar kraj | 2026-09-15 16:00 UTC | minister wiodący → RZZK |

Uwaga dla zgłoszeń 112/PSP: próg produkcyjny `>25` w jednej gminie w 15 minut nie ma trafień w danych syntetycznych; najwyższy peak gminny wynosi 3. Dlatego w funkcji demo użyto `>2`, aby reguła faktycznie zadziałała na danych podczas pokazu.

### Ręczne dokończenie powiadomień w UI Activator

Ścieżka workspace: [OL-ZK-Demo-COP24](https://app.fabric.microsoft.com/groups/8ea0556f-7368-4b36-ad84-adf995e19a80).

Wariant A — od Eventstream:

1. Otwórz workspace → **OL_COP24_Eventstream**.
2. Wybierz źródło/destynację strumienia `hydro_readings_rt` i akcję **Set alert** / **New Activator alert**.
3. Jako cel wybierz istniejący Activator **OL_COP24_Activator**.
4. Utwórz obiekty i reguły:
   - `HydroAlarm`: pole `level_cm`, warunek `Becomes greater than` odpowiedni próg alarmowy; dla szybkiego testu użyj stałego progu 340 cm albo danych z funkcji `alert_hydro_alarm()`.
   - `HydroRapidRise`: pole/miara przyrostu, warunek `>20` cm w oknie 30 min.
5. Akcja: Teams albo e-mail do kanału demo; tytuł w formacie z sekcji „Format powiadomienia”.

Wariant B — od Real-Time Dashboard:

1. Otwórz workspace → **OL_COP24_Dashboard**.
2. Dodaj kafelek/tabelę dla każdej funkcji, np. `alert_power_outage() | top 100 by alert_ts desc`.
3. Na kafelku wybierz **Set alert**.
4. Ustaw warunek „liczba wierszy > 0” lub „`current_value` przekracza `threshold_value`”, cooldown zgodnie z zasadami powyżej.
5. Połącz alert z **OL_COP24_Activator** i wybierz kanał powiadomienia.

Rekomendowane kafelki do alertów UI:

```kusto
alert_hydro_alarm() | top 100 by alert_ts desc
alert_hydro_rapid_rise() | top 100 by alert_ts desc
alert_incident_spike() | top 100 by alert_ts desc
alert_power_outage() | top 100 by alert_ts desc
alert_telco_coverage_drop() | top 100 by alert_ts desc
alert_disinformation_z20() | top 100 by alert_ts desc
alert_escalation_rzzk() | top 100 by alert_ts desc
```

Każde powiadomienie powinno używać pól `alert_rule`, `alert_severity`, `alert_ts`, `gmina_code`, `current_value`, `threshold_value`, `spo` i `message`. Deduplikację prowadź po `alert_key`.
