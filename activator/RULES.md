# 🚨 Reguły Data Activator / Reflex

> Reguły są demonstracyjne. W produkcji progi zatwierdza właściciel procesu i minister/wojewoda zgodnie z procedurami.

## 1. Stan alarmowy wodowskazu
Cel: natychmiast uruchomić obieg informacji. Źródło: `hydro_readings`. KQL: `hydro_readings | where level_cm >= alarm_level_cm`. Próg: jeden odczyt, bo przekroczenie stanu alarmowego jest zdarzeniem formalnym. Odbiorca: WCZK, PCZK, RCB. Treść: „Wodowskaz {gauge_id} przekroczył alarm: {level_cm} cm”. Akcja: SPO-12 i SPO-3.

## 2. Gwałtowny przyrost poziomu
Cel: wykryć dynamikę zanim pojawi się szczyt. KQL: `hydro_readings | order by gauge_id,timestamp | extend delta=level_cm-prev(level_cm) | where delta > 20`. Próg 20 cm/30 min jest konserwatywny w demie. Odbiorca: IMGW/Wody Polskie/RCB. Akcja: weryfikacja prognozy i komunikat.

## 3. Zgłoszenia 112/PSP w gminie
Cel: powiązać zjawisko z wpływem na ludność. KQL: `incident_reports | summarize c=count() by bin(timestamp,15m), gmina_code | where c > 25`. Próg 25 oznacza przeciążenie lokalne. W danych peak 15-min wynosi 12, więc w demo można obniżyć próg testowy. Akcja: SPO-3, SPO-12.

## 4. Odbiorcy bez prądu
Cel: aktywować Z07 i IK. KQL: `power_grid_events | summarize customers=sum(customers_offline) by bin(timestamp,1h), gmina_code | where customers > 5000`. Próg: 5000 odbiorców to skala istotna społecznie. W danych szczyt godzinowy wynosi 24057. Odbiorca: PSE/OSD, wojewoda, RCB. Akcja: SPO-10.

## 5. Brak łączności
Cel: wykryć utratę kanałów alarmowania. KQL: `telecom_events | where coverage_pct < 40 or base_stations_down >= 5`. Próg: poniżej 40% oznacza problem z dotarciem do ludności. Minimalne pokrycie w danych: 22.6%. Akcja: SPO-10 i SPO-3.

## 6. Dezinformacja Z20
Cel: uruchomić komunikację społeczną. KQL: `media_signals | where disinformation_flag == true and reach > 50000`. W danych jest 363 sygnałów i zasięg 39854793. Odbiorca: CIR, NASK, RCB. Akcja: sprostowanie i SPO-3.

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
