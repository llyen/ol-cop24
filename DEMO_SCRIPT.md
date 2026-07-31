# 🎬 Scenariusz demo 15–20 min — COP-24

> ⚠️ Wszystkie dane są syntetyczne (`seed=42`). Scenariusz służy pokazaniu, jak Microsoft Fabric może wspierać RCB / RZZK w budowie wspólnego obrazu sytuacji kraju. Dane liczbowe w tej narracji pochodzą z wygenerowanych plików w `datasets/` i wyników `datasets/derived/`.

## 👥 Obsada ról i sposób grania

| Rola | Kto gra | Cel w narracji | Ton wypowiedzi |
|---|---|---|---|
| Prezenter | prowadzący demo | prowadzi przez architekturę, akty i wartość biznesową | spokojny, decyzyjny |
| Oficer dyżurny RCB | operator dashboardu | klika filtry, pokazuje alerty, odpowiada na pytania techniczne | operacyjny |
| Dyrektor RCB | decydent krajowy | pyta „czy eskalować?” i „na jakiej podstawie?” | wymaga zwięzłości |
| Wojewoda | perspektywa regionalna | potwierdza lokalny obraz sytuacji i potrzeby zasobowe | praktyczny |
| Minister | minister wiodący / członek RZZK | pyta o SPO, koszty, odpowiedzialność i komunikację | strategiczny |

## ⏱️ Otwarcie — 90 sekund

**Kwestia do wypowiedzenia:** „Pokazujemy demonstrator COP-24: wspólny obraz sytuacji dla scenariusza *Powódź Wrzesień*. To nie jest system produkcyjny i nie są to dane operacyjne, ale kompletna makieta decyzyjna: źródła, strumień, Eventhouse, dashboard, Data Agent, Activator i aplikacja Pulpit RZZK. Kluczowe pytanie brzmi: czy decydent może szybciej i lepiej uzasadnić eskalację poziomu reagowania?”

**Co kliknąć:** `README.md` → diagram architektury, potem Real-Time Dashboard → strona `Obraz kraju`.

**Co widz zobaczy:** mapa kraju, tabela źródeł, KPI. W repo jest 2477 gmin, 380 powiatów, 120 wodowskazów, 449400 odczytów hydro i 118940 obserwacji pogody.

## 🧭 Akty demo wg osi czasu

### I. D-3 — sygnały wczesne

**Kwestia do wypowiedzenia:** „Na tym etapie nie sprzedaję tezy, że mamy kryzys. Pokazuję, że Fabric zbiera sygnały ostrzegawcze zanim ktokolwiek zwoła sztab. Decydent widzi kraj, a nie pojedynczy raport z jednej instytucji.”

**Co kliknąć:** Strona `Obraz kraju`, filtr `hazard_code=Z02`, zakres D-3; kafel `Opady i poziomy`. Ustaw filtr czasu zgodnie z nazwą aktu, pozostaw `hazard_code=Z02`, a dla drill-down użyj województw `02` i `16`.

**Co widz zobaczy:** KIS krajowy 2.3, brak gmin powyżej KIS 25, ale w strumieniu pogody widać narastające opady. Na osi hydrologicznej piki przechodzą kolejno: Kłodzko 2026-09-15T10:05:00+02:00 poziom 493 cm, Nysa 2026-09-16T00:10:00+02:00 poziom 512 cm, Opole 2026-09-16T14:15:00+02:00 poziom 520 cm, Wrocław 2026-09-17T12:05:00+02:00 poziom 536 cm.

**Jakie liczby powiedzieć:** wykorzystaj realne wartości z danych: liczba gmin w alarmie łącznie 10, incydenty łącznie 4943, poszkodowani/objęci zgłoszeniami 263001, zdarzenia telco 351 oraz sygnały medialne 3028 w tym 363 z flagą dezinformacji.

### II. D-1 — ostrzegawcze i pierwsze incydenty

**Kwestia do wypowiedzenia:** „Tu zaczyna się przewaga wspólnego obrazu sytuacji: nie czekamy na raport końcowy, tylko widzimy trend. Stany ostrzegawcze i pierwsze zgłoszenia zaczynają układać się w jeden wzorzec przestrzenny.”

**Co kliknąć:** Strona `Hydrologia`, kafel `Mapa wodowskazów`; potem `Zgłoszenia 112/PSP 15 min`. Ustaw filtr czasu zgodnie z nazwą aktu, pozostaw `hazard_code=Z02`, a dla drill-down użyj województw `02` i `16`.

**Co widz zobaczy:** 2 gminy osiągają alarm w danych hydro; liczba incydentów dziennych: 284. Na osi hydrologicznej piki przechodzą kolejno: Kłodzko 2026-09-15T10:05:00+02:00 poziom 493 cm, Nysa 2026-09-16T00:10:00+02:00 poziom 512 cm, Opole 2026-09-16T14:15:00+02:00 poziom 520 cm, Wrocław 2026-09-17T12:05:00+02:00 poziom 536 cm.

**Jakie liczby powiedzieć:** wykorzystaj realne wartości z danych: liczba gmin w alarmie łącznie 10, incydenty łącznie 4943, poszkodowani/objęci zgłoszeniami 263001, zdarzenia telco 351 oraz sygnały medialne 3028 w tym 363 z flagą dezinformacji.

### III. D0 — alarmy, kaskada IK i rekomendacja RZZK

**Kwestia do wypowiedzenia:** „To jest moment decyzyjny. System nie mówi premierowi, co ma zdecydować, ale pokazuje, że lokalne poziomy reagowania już nie wystarczają, bo jednocześnie dotknięte są hydrologia, energetyka, łączność i ochrona ludności.”

**Co kliknąć:** Strony `Hydrologia`, `Infrastruktura krytyczna`, `RZZK i SPO`; kafel `Ostatnie eskalacje`. Ustaw filtr czasu zgodnie z nazwą aktu, pozostaw `hazard_code=Z02`, a dla drill-down użyj województw `02` i `16`.

**Co widz zobaczy:** D0: 4 gminy w alarmie, 571 incydentów, max lokalny KIS 78.6. Eskalacja minister→RZZK jest o 18:00. Na osi hydrologicznej piki przechodzą kolejno: Kłodzko 2026-09-15T10:05:00+02:00 poziom 493 cm, Nysa 2026-09-16T00:10:00+02:00 poziom 512 cm, Opole 2026-09-16T14:15:00+02:00 poziom 520 cm, Wrocław 2026-09-17T12:05:00+02:00 poziom 536 cm.

**Jakie liczby powiedzieć:** wykorzystaj realne wartości z danych: liczba gmin w alarmie łącznie 10, incydenty łącznie 4943, poszkodowani/objęci zgłoszeniami 263001, zdarzenia telco 351 oraz sygnały medialne 3028 w tym 363 z flagą dezinformacji.

### IV. D+1…D+3 — ewakuacje, siły i Z20

**Kwestia do wypowiedzenia:** „Teraz pokazujemy decydentowi nie samą wodę, tylko skutki społeczne. Ewakuacja, prąd, telekomunikacja i dezinformacja są w jednym widoku, więc rozmowa RZZK przechodzi od opisu zdarzeń do priorytetów działania.”

**Co kliknąć:** Strony `Obraz kraju`, `Infrastruktura krytyczna`, `Z20 Dezinformacja`; filtr D+1…D+3. Ustaw filtr czasu zgodnie z nazwą aktu, pozostaw `hazard_code=Z02`, a dla drill-down użyj województw `02` i `16`.

**Co widz zobaczy:** Peak: 24057 odbiorców bez prądu w godzinie 2026-09-17T08:00; 56212 osób w statusach ewakuacji; minimalne pokrycie telco 22.6%. Na osi hydrologicznej piki przechodzą kolejno: Kłodzko 2026-09-15T10:05:00+02:00 poziom 493 cm, Nysa 2026-09-16T00:10:00+02:00 poziom 512 cm, Opole 2026-09-16T14:15:00+02:00 poziom 520 cm, Wrocław 2026-09-17T12:05:00+02:00 poziom 536 cm.

**Jakie liczby powiedzieć:** wykorzystaj realne wartości z danych: liczba gmin w alarmie łącznie 10, incydenty łącznie 4943, poszkodowani/objęci zgłoszeniami 263001, zdarzenia telco 351 oraz sygnały medialne 3028 w tym 363 z flagą dezinformacji.

### V. D+4…D+10 — stabilizacja i odbudowa

**Kwestia do wypowiedzenia:** „W ostatnim akcie nie świętujemy końca demo. Pokazujemy przejście z reagowania do odbudowy: gdzie utrzymać zasoby, gdzie odtwarzać infrastrukturę i które decyzje trzeba pozostawić w śladzie audytowym.”

**Co kliknąć:** Strona `Obraz kraju`, zakres D+4…D+10; kafle KIS, incydenty i zasoby. Ustaw filtr czasu zgodnie z nazwą aktu, pozostaw `hazard_code=Z02`, a dla drill-down użyj województw `02` i `16`.

**Co widz zobaczy:** KIS krajowy schodzi z 3.3 do 2.3; liczba gmin powyżej KIS 45 spada z 17 do 0. Na osi hydrologicznej piki przechodzą kolejno: Kłodzko 2026-09-15T10:05:00+02:00 poziom 493 cm, Nysa 2026-09-16T00:10:00+02:00 poziom 512 cm, Opole 2026-09-16T14:15:00+02:00 poziom 520 cm, Wrocław 2026-09-17T12:05:00+02:00 poziom 536 cm.

**Jakie liczby powiedzieć:** wykorzystaj realne wartości z danych: liczba gmin w alarmie łącznie 10, incydenty łącznie 4943, poszkodowani/objęci zgłoszeniami 263001, zdarzenia telco 351 oraz sygnały medialne 3028 w tym 363 z flagą dezinformacji.

## 🤖 Pytania do Data Agenta — do zadania na żywo

| # | Pytanie | Oczekiwana odpowiedź |
|---:|---|---|
| 1 | „Które gminy weszły w stan alarmowy i kiedy?” | Agent powinien wskazać 10 gmin oraz pierwsze piki na osi Kłodzko→Nysa→Opole→Wrocław. |
| 2 | „Dlaczego rekomendujesz eskalację do RZZK?” | Bo w D0/D+1 występuje współwystępowanie Z02, Z07, Z12 i Z20, a eskalacja minister→RZZK jest zapisana w `escalation_events`. |
| 3 | „Jaki był szczyt awarii zasilania?” | 24057 odbiorców bez prądu w godzinie 2026-09-17T08:00. |
| 4 | „Ile osób objęto ewakuacją?” | 56212 osób w najnowszych statusach ewakuacji. |
| 5 | „Gdzie KIS był najwyższy?” | Maksymalny lokalny KIS osiągnął 100 w dniu 2026-09-16; województwo opolskie miało wtedy wysoki pik lokalny. |
| 6 | „Czy telekomunikacja jest problemem operacyjnym?” | Tak, minimalne pokrycie spadło do 22.6%, a 80 gmin miało zdarzenia z pokryciem poniżej 50%. |
| 7 | „Ile było sygnałów dezinformacyjnych?” | 363 sygnałów z flagą Z20 i łączny zasięg 39854793. |
| 8 | „Czy liczba incydentów rośnie po przekroczeniach hydro?” | Tak, D0 ma 571 incydentów, D+1 559, D+2 599. |
| 9 | „Jakie SPO powinny być na stole RZZK?” | SPO-1, SPO-2, SPO-3, SPO-10, SPO-12 oraz monitorowanie SPO-5. |
| 10 | „Czy algorytm zastępuje wojewodę albo ministra?” | Nie. Agent generuje rekomendację i uzasadnienie; decyzję podejmuje człowiek i zapisuje ją w rejestrze decyzji. |
| 11 | „Jakie dane są syntetyczne?” | Wszystkie: 581412 rekordów w CSV/JSONL, zero danych osobowych i zero danych operacyjnych. |
| 12 | „Co zmieniło się między D0 i D+3?” | KIS lokalny osiąga maksimum 100, potem spada; jednocześnie utrzymują się ewakuacje i skutki infrastrukturalne. |

## ✨ Wow moments

1. **Fala z opóźnieniem czasowym.** Decydent widzi nie statyczną mapę, lecz propagację z Kłodzka przez Nysę i Opole do Wrocławia. To natychmiast buduje zaufanie, bo obraz jest zgodny z intuicją hydrologiczną.
2. **Kaskada infrastruktury krytycznej.** Peak 24057 odbiorców bez prądu i minimalne pokrycie telco 22.6% pokazują, że powódź nie jest tylko problemem wody. To uzasadnia udział wielu ministrów.
3. **Automatyczne SPO.** Alert nie kończy się czerwonym kafelkiem; wskazuje SPO i odbiorców powiadomień. Dla decydenta oznacza to przejście od „wiem” do „działam”.
4. **Data Agent tłumaczy „dlaczego”.** Zamiast szukać raportów, dyrektor pyta językiem naturalnym i dostaje liczby oraz podstawę rekomendacji.
5. **Dziennik audytowy decyzji.** Pulpit RZZK pokazuje kto, kiedy, na jakiej podstawie i co zdecydował. To jest ważne przy rozliczalności działań administracji.

## 💼 Wartość biznesowa

- **Czas do decyzji:** jeden pulpit redukuje ręczne scalanie meldunków z wielu źródeł. W demie decyzja o RZZK wynika z jednego przebiegu osi czasu i gotowych reguł.
- **Jakość podstawy decyzyjnej:** liczby, źródła i reguły są widoczne; decydent może sprawdzić, czy rekomendacja wynika z hydro, incydentów, energii, telekom czy ewakuacji.
- **Ślad audytowy:** decyzje są zapisywane w modelu write-back aplikacji, z linkiem do alertu, SPO i danych źródłowych.
- **Zgodność z ustawą o ZK i KPZK:** narracja respektuje fazy zapobieganie→przygotowanie→reagowanie→odbudowa oraz poziomy gmina→powiat→wojewoda→minister→RZZK.

## 🧯 Plan B

| Awaria | Co zrobić | Co powiedzieć |
|---|---|---|
| Strumień nie działa | uruchom `simulate_realtime.py --dry-run --output replay.jsonl` i pokaż plik | „Mechanizm ingestii jest wymienny; dane i model decyzyjny pozostają te same.” |
| Brak sieci | pracuj z lokalnymi JSONL/CSV i `datasets/derived` | „Demo nie zależy od internetu, bo wartości są deterministyczne.” |
| Dane się nie odświeżają | odśwież dashboard ręcznie, pokaż KQL Queryset | „Tu widać warstwę prawdy: Eventhouse i zapytanie.” |
| Data Agent nie odpowiada | użyj tabeli pytań powyżej i pokaż KQL | „Agent jest interfejsem, nie jedynym źródłem odpowiedzi.” |
| Activator bez Teams | pokaż treść alertu z `activator/RULES.md` | „Integracja kanału powiadomień jest ostatnią milą.” |

## ❓ Najczęstsze pytania decydenta i odpowiedzi

1. **Skąd są dane?** W demie są syntetyczne; produkcyjnie byłyby to integracje IMGW-PIB, Wody Polskie, PSP/112, PSE/OSD, operatorzy telco, WCZK/PCZK i monitoring mediów.
2. **Czy to zastępuje systemy służb?** Nie. Fabric pełni warstwę integracji, analityki i obrazu wspólnego, nie zastępuje systemów źródłowych.
3. **Jak chronimy informacje?** W produkcji: klasyfikacja, Purview, etykiety wrażliwości, RBAC, sieci prywatne, logowanie dostępu i retencja.
4. **Ile kosztuje wdrożenie?** Zależy od wolumenów i SLA; architektura pozwala skalować Eventhouse, Lakehouse i Power BI niezależnie.
5. **Ile trwa MVP?** Dla pierwszego województwa i kilku źródeł: tygodnie, nie lata; pełny krajowy program wymaga uzgodnień międzyinstytucjonalnych.
6. **Co jeśli dane są niepełne?** Reguły powinny pokazywać kompletność danych i poziom pewności; brak danych nie może być traktowany jako brak ryzyka.
7. **Czy algorytm zastępuje człowieka?** Nie. Rekomenduje, wyjaśnia i dokumentuje; decyzję podejmuje uprawniony organ.
8. **Czy można dodać inne zagrożenia KPZK?** Tak, `dim_hazard` zawiera 20 zagrożeń, a model wspiera Z02, Z07, Z12 i Z20 w tym scenariuszu.
9. **Czy działa przy awarii regionu?** Produkcyjnie trzeba dodać DR, replikację i tryb degradacji; demo pokazuje wzorzec logiczny.

## ✅ Checklista przed demo

| Kiedy | Czynność |
|---|---|
| T-45 min | `python generate_datasets.py`, sprawdź `datasets/README.md` |
| T-35 min | `python notebooks/02_situation_index.py`, potem `python notebooks/03_escalation_recommendation.py` |
| T-30 min | uruchom Eventhouse i dashboard, otwórz strony w kartach |
| T-20 min | test `simulate_realtime.py --dry-run` |
| T-15 min | sprawdź Data Agent pytaniami 1, 3 i 9 |
| T-10 min | przygotuj plan B: lokalne `datasets/derived` i pliki KQL |
| T-5 min | ustaw pierwszy widok `Obraz kraju`, filtr Z02, D-3 |
