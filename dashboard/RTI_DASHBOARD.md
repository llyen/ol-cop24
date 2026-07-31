# 📊 Real-Time Dashboard COP-24

Dashboard jest ekranem operacyjnym dla oficera dyżurnego RCB i decydentów. Ma pięć stron, wspólne parametry `voivodeship_code`, `hazard_code`, `time_range` i auto-odświeżanie 30–60 sekund w czasie replay.

## Strona 1 — Obraz kraju
**Cel:** szybka odpowiedź, czy sytuacja wymaga eskalacji. **Odbiorca:** Dyrektor RCB, minister. **Układ:** górny pasek KPI, mapa po lewej, timeline po prawej, tabela top alertów na dole. **Kafelki:** KIS krajowy (Card, z derived/Lakehouse), Gminy w alarmie (Card, query z `hydro_latest`), Odbiorcy bez prądu (Line chart z sekcji power w `03_dashboard_queries.kql`), Ostatnie eskalacje (Table z sekcji escalation). **Co pokazuje:** stan kraju i kierunek decyzji.

## Strona 2 — Hydrologia
**Cel:** zobaczyć falę i progi. **Odbiorca:** oficer dyżurny, wojewoda. **Kafelki:** Mapa wodowskazów (Map, pierwsze zapytanie `hydro_latest`), Trend poziomu (Line chart po `gauge_id`), Tabela progów (Table), Fala Kłodzko→Nysa→Opole→Wrocław (Line chart filtrowany do wodowskazów trasy). **Auto-odświeżanie:** 30 s podczas replay. **Interakcje:** kliknięcie wodowskazu filtruje gminę.

## Strona 3 — Infrastruktura krytyczna
**Cel:** pokazać skutki Z07 i Z12. **Kafelki:** Odbiorcy bez prądu (Line chart z `power_grid_events`), Gminy z pokryciem <50% (Table z `telecom_events`), Korelacja flood-energy-telco (Table z `04_anomaly_detection.kql`), ETA przywrócenia (Bar chart). **Odbiorca:** minister, wojewoda, operatorzy IK.

## Strona 4 — RZZK i SPO
**Cel:** przejście od obrazu do decyzji. **Kafelki:** Ostatnie eskalacje (Table z `escalation_events`), Rekomendowane SPO (Table), Licznik KIS >45 i >85 (Cards), Link do Fabric App. **Opis:** ta strona jest używana w akcie III demo, gdy prowadzący mówi o minister→RZZK.

## Strona 5 — Z20 Dezinformacja
**Cel:** pokazać ryzyko komunikacyjne. **Kafelki:** Sygnały dezinformacyjne (Card), Zasięg narracji (Line/Area), Kanały (Donut), Tematy (Bar), Alert SPO-3 (Table). **Filtry:** `hazard_code=Z20`, zakres D0…D+3.

## Parametry i filtry

`voivodeship_code` filtruje przez relację TERYT; `hazard_code` domyślnie Z02, ale dla dezinformacji Z20; `time_range` ma presety D-3, D-1, D0, D+1…D+3, D+4…D+10. Każdy kafel ma podpis: źródło, opóźnienie, czas ostatniego odświeżenia.

## Mapowanie do KQL

Zapytania bazowe są w `kql/03_dashboard_queries.kql`: mapa hydro, agregacja incydentów 15 min, energia, telco poniżej 50%, eskalacje. Dla kafli KIS użyj plików `datasets/derived` albo tabel Lakehouse wygenerowanych notebookami. Dla korelacji użyj `kql/04_anomaly_detection.kql`.

## Zasady prezentacji

Kolory: zielony normal, żółty warning, czerwony alarm, brązowy critical. Nie pokazuj surowej tabeli jako pierwszego ekranu dla decydenta; surowe dane są drill-downem. W każdym widoku trzymaj jedną narrację: „co się dzieje, co to oznacza, co rekomendujemy”.

## Szczegółowy układ kafelków

Na stronie `Obraz kraju` pierwszy rząd: cztery KPI po 25% szerokości. Drugi rząd: mapa 60%, timeline eskalacji 40%. Trzeci rząd: tabela top gmin i panel rekomendowanych SPO. Na stronie `Hydrologia` mapa zajmuje lewą połowę, wykres fali prawą górę, tabela wodowskazów prawy dół. Na stronie IK użyj dwóch wykresów liniowych obok siebie i tabeli korelacji pod spodem.

## Opisy kafelków dla operatora

Kafel `Mapa wodowskazów` pokazuje status względem progów i nie jest prognozą. Kafel `Zgłoszenia 112/PSP` pokazuje tempo obciążenia służb, nie pełną liczbę poszkodowanych. Kafel `Odbiorcy bez prądu` używa sumy zdarzeń w oknie i w produkcji wymaga deduplikacji stanu. Kafel `Z20` pokazuje sygnały medialne do triage, nie rozstrzyga prawdziwości informacji bez analityka.

## Tryb prezentacyjny

Przed wejściem decydenta ustaw zakres D-3 i stronę `Obraz kraju`. W akcie II przejdź do `Hydrologia`, w akcie III do `RZZK i SPO`, w akcie IV do `Infrastruktura krytyczna` i `Z20`. Nie klikaj więcej niż dwa filtry na żywo; resztę przygotuj jako bookmarki. Każdy bookmark powinien mieć nazwę aktu demo.

## Auto-odświeżanie i wydajność

Dla replay lokalnego wystarczy 30 sekund. Dla produkcji częstotliwość powinna zależeć od kosztu zapytań i oczekiwanej latencji źródeł. Kafle z `make-series` i korelacją uruchamiaj na ograniczonym zakresie czasu, a nie na całej retencji. Najdroższe zapytania przenieś do widoków materializowanych albo tabel derived.

## Bookmarki do scenariusza

Utwórz bookmark `Akt I - D-3`, `Akt II - D-1`, `Akt III - D0 RZZK`, `Akt IV - D+1 D+3`, `Akt V - odbudowa`. Każdy bookmark zapisuje zakres czasu, filtr zagrożenia i stronę dashboardu. Dzięki temu prezenter nie traci czasu na ręczne ustawianie parametrów i może skupić się na narracji.

## Kryteria jakości dashboardu

Dashboard jest gotowy do demo, jeśli na ekranie głównym widać co najmniej: KIS, gminy w alarmie, ewakuowanych, odbiorców bez prądu, ostatnią eskalację i link do Pulpitu RZZK. Kafle nie mogą mieć tytułów technicznych typu `query1`; tytuł ma mówić językiem decydenta. Każdy kafel musi mieć podpis „źródło: Eventhouse/Lakehouse, dane syntetyczne”.

## Uwagi dla prowadzącego

Nie pokazuj wszystkich stron od razu. Strona `Hydrologia` buduje wiarygodność techniczną, `Infrastruktura krytyczna` uzasadnia udział wielu ministrów, `RZZK i SPO` uzasadnia decyzję, a `Z20` pokazuje, że komunikacja społeczna jest częścią reagowania. Jeśli czas jest krótki, pomiń szczegóły Power BI i przejdź bezpośrednio do aplikacji.
