# 🤖 Prompt Rayfin / Fabric Apps — „Pulpit RZZK”

Zbuduj aplikację Microsoft Fabric App w języku polskim dla scenariusza **COP-24 — Wspólny Obraz Sytuacji**. Aplikacja ma wspierać RCB i RZZK podczas scenariusza „Powódź Wrzesień”: D-3 sygnały wczesne, D-1 stany ostrzegawcze, D0 alarm i eskalacja, D+1…D+3 ewakuacje i infrastruktura krytyczna, D+4…D+10 stabilizacja.

Kontekst domenowy: poziomy reagowania to gmina → powiat → wojewoda → minister wiodący → RZZK. Uwzględnij zagrożenia KPZK Z02 Powódź, Z07 Energetyka, Z12 Telekomunikacja i Z20 Dezinformacja. Używaj SPO-1, SPO-2, SPO-3, SPO-10, SPO-12 oraz monitoruj SPO-5.

Źródła danych: Eventhouse tabele `hydro_readings(timestamp,gauge_id,gmina_code,level_cm,warning_level_cm,alarm_level_cm,trend)`, `incident_reports(timestamp,incident_id,gmina_code,priority,affected_people,status)`, `power_grid_events(timestamp,gmina_code,customers_offline,eta_restore_min,cause)`, `telecom_events(timestamp,gmina_code,coverage_pct,base_stations_down,cause)`, `media_signals(timestamp,topic,reach,disinformation_flag,hazard_code)`, `escalation_events(timestamp,from_level,to_level,area,recommended_spo,reason)`. Lakehouse tabele `dim_voivodeship`, `dim_powiat`, `dim_gmina`, `dim_spo`, `kis_country`, `kis_voivodeship`, `kis_gmina`, `escalation_recommendations`, `decision_log`.

Zaprojektuj ekrany: 1) Sytuacja krajowa, 2) Karta województwa, 3) Rekomendowane SPO, 4) Rejestr decyzji, 5) Zwołaj RZZK (SPO-1). Użyj ikon w nagłówkach, statusów `normal/warning/alarm/critical`, kart KPI, map i tabel. Każda rekomendacja ma mieć sekcję „Dlaczego?” z danymi źródłowymi.

Role: Dyrektor RCB zatwierdza i zwołuje RZZK; oficer dyżurny triage i przygotowuje brief; wojewoda widzi swoje województwo i wnioskuje o zasoby; minister akceptuje działania resortowe. Decyzji nie wolno usuwać, tylko wersjonować.

Akcje write-back: `create_decision_log`, `assign_spo_owner`, `request_resources`, `notify_teams`, `generate_prime_minister_brief`. Model decyzji: `decision_id`, `version`, `timestamp`, `decision_maker`, `role`, `decision_text`, `scope`, `related_spo`, `source_alert`, `evidence_query`, `audit_hash`.

W danych demo realne wartości do pokazania: 10 gmin w alarmie łącznie, szczyt energii 139 539 odbiorców bez prądu w dobie kulminacji, 15 445 osób w ewakuacjach, 335 sygnałów dezinformacji, maksymalny lokalny KIS 86,3 (2026-09-17). Nie wymyślaj innych liczb: jeśli aplikacja nie ma danych, pokaż „brak danych” i link do źródła.

UX: język prosty, decyzyjny; pierwszy ekran ma odpowiadać w 30 sekund, czy potrzebne jest RZZK. Dodaj tryb offline: tylko odczyt ostatnich danych i kolejka decyzji. Dodaj obsługę błędów: brak danych, brak uprawnień, konflikt wersji, nieudane powiadomienie.

## Dodatkowe instrukcje dla generatora

Nie projektuj aplikacji jako zwykłej listy tabel. Najważniejsza jest droga użytkownika: zobacz zagrożenie, zrozum uzasadnienie, wybierz SPO, zapisz decyzję, powiadom właściwych ludzi. Każdy ekran ma mieć przycisk „pokaż dane źródłowe” oraz etykietę „dane syntetyczne”.

Wygeneruj komponent `DecisionEvidencePanel`, który pokazuje: źródłowe zapytanie, timestamp danych, listę składowych KIS oraz ostatnie zdarzenia eskalacji. Wygeneruj komponent `SpoChecklist`, który ma statusy: nie rozpoczęto, w toku, wymaga decyzji, zakończono. Wygeneruj komponent `OfflineQueue`, który przechowuje decyzje lokalnie do synchronizacji.

Zastosuj walidacje: pola wymagane nie mogą być puste; `decision_text` minimum 20 znaków; decyzja zatwierdzona wymaga roli Dyrektor RCB albo Minister; wojewoda nie może zmienić danych poza swoim województwem; każda korekta decyzji tworzy nową wersję.

Dodaj dane przykładowe do makiety: stan alarmowy w 10 gminach, szczyt energii 139 539 odbiorców w dobie kulminacji, 15 445 osób w ewakuacjach, 335 sygnałów dezinformacji, maksymalny lokalny KIS 86,3 (2026-09-17). Jeśli połączenie danych zwróci null, pokaż pusty stan z instrukcją „sprawdź ingest lub zakres czasu”.

Interfejs ma być gotowy do prezentacji przed decydentem: mało tekstu na ekranie głównym, dużo uzasadnienia po kliknięciu. Użyj emoji w nagłówkach, ale zachowaj powagę administracyjną. Nie używaj angielskich etykiet dla użytkownika końcowego poza nazwami technicznymi tabel i kolumn.

## Kryteria akceptacji wygenerowanej aplikacji

Aplikacja jest poprawna, jeśli użytkownik może w mniej niż trzy kliknięcia przejść od alertu do projektu decyzji, a następnie zapisać wpis audytowy. Ekran główny musi mieć widoczne KPI bez przewijania. Każdy rekord write-back musi zawierać `timestamp`, rolę, użytkownika, podstawę danych i wersję. Wygeneruj przykładowe stany pustych ekranów, komunikaty błędów i potwierdzenie akcji „Zwołaj RZZK”.

Dodaj krótkie teksty pomocy przy polach: „Podstawa decyzji”, „Powiązana SPO”, „Zakres terytorialny” i „Uzasadnienie”. Teksty pomocy mają tłumaczyć operatorowi, że decyzja ma być zrozumiała po audycie, także dla osoby, która nie widziała dashboardu na żywo.
