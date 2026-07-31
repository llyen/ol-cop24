# ⚙️ Setup Microsoft Fabric krok po kroku

> ⚠️ Demo syntetyczne; nie wgrywaj poświadczeń do repo. Nazwy poniżej są referencyjne i warto ich użyć bez zmian, aby dokumentacja, KQL, dashboard i narracja mówiły tym samym językiem.

## 1. Workspace i capacity

**Cel:** Wspólny kontener artefaktów Fabric.

**Czynności:** Utworzyć `OL-COP24-Demo` na capacity F2+ lub większej. Dodatkowo nazwij artefakt dokładnie jak w tej instrukcji, dodaj opis `COP-24 demo / dane syntetyczne` i ogranicz dostęp do zespołu demonstracyjnego.

**Oczekiwany rezultat:** Workspace widoczny w portalu.

**Orientacyjny czas:** 5 min.

**Kontrola:** po wykonaniu kroku zapisz zrzut lub notatkę w checklistcie demo. Jeśli krok dotyczy danych, użyj małego zakresu czasu zanim uruchomisz pełny replay.

## 2. Eventhouse

**Cel:** Telemetria real-time i zapytania niskiej latencji.

**Czynności:** Utworzyć `OL_COP24_Eventhouse` i KQL Database `OL_COP24_KQL`. Dodatkowo nazwij artefakt dokładnie jak w tej instrukcji, dodaj opis `COP-24 demo / dane syntetyczne` i ogranicz dostęp do zespołu demonstracyjnego.

**Oczekiwany rezultat:** Baza KQL gotowa na skrypty.

**Orientacyjny czas:** 5 min.

**Kontrola:** po wykonaniu kroku zapisz zrzut lub notatkę w checklistcie demo. Jeśli krok dotyczy danych, użyj małego zakresu czasu zanim uruchomisz pełny replay.

## 3. Eventstream custom endpoint

**Cel:** Przyjęcie JSONL z symulatora.

**Czynności:** Utworzyć `ol-cop24-eventstream`, źródło Custom App/Event Hub, destination Eventhouse. Dodatkowo nazwij artefakt dokładnie jak w tej instrukcji, dodaj opis `COP-24 demo / dane syntetyczne` i ogranicz dostęp do zespołu demonstracyjnego.

**Oczekiwany rezultat:** Endpoint i connection string dostępne.

**Orientacyjny czas:** 10 min.

**Kontrola:** po wykonaniu kroku zapisz zrzut lub notatkę w checklistcie demo. Jeśli krok dotyczy danych, użyj małego zakresu czasu zanim uruchomisz pełny replay.

## 4. KQL 01

**Cel:** Tabele i mapowania JSON.

**Czynności:** Uruchomić `kql/01_create_tables.kql`. Dodatkowo nazwij artefakt dokładnie jak w tej instrukcji, dodaj opis `COP-24 demo / dane syntetyczne` i ogranicz dostęp do zespołu demonstracyjnego.

**Oczekiwany rezultat:** 9 tabel strumieniowych.

**Orientacyjny czas:** 5 min.

**Kontrola:** po wykonaniu kroku zapisz zrzut lub notatkę w checklistcie demo. Jeśli krok dotyczy danych, użyj małego zakresu czasu zanim uruchomisz pełny replay.

## 5. KQL 02

**Cel:** Widoki latest i agregacje 15-min.

**Czynności:** Uruchomić `kql/02_update_policies.kql`. Dodatkowo nazwij artefakt dokładnie jak w tej instrukcji, dodaj opis `COP-24 demo / dane syntetyczne` i ogranicz dostęp do zespołu demonstracyjnego.

**Oczekiwany rezultat:** Materialized views gotowe.

**Orientacyjny czas:** 5 min.

**Kontrola:** po wykonaniu kroku zapisz zrzut lub notatkę w checklistcie demo. Jeśli krok dotyczy danych, użyj małego zakresu czasu zanim uruchomisz pełny replay.

## 6. Lakehouse

**Cel:** Wymiary referencyjne i wyniki KIS.

**Czynności:** Utworzyć `OL_COP24_Lakehouse`, wgrać CSV z `datasets/`. Dodatkowo nazwij artefakt dokładnie jak w tej instrukcji, dodaj opis `COP-24 demo / dane syntetyczne` i ogranicz dostęp do zespołu demonstracyjnego.

**Oczekiwany rezultat:** Pliki widoczne w Files/datasets.

**Orientacyjny czas:** 10 min.

**Kontrola:** po wykonaniu kroku zapisz zrzut lub notatkę w checklistcie demo. Jeśli krok dotyczy danych, użyj małego zakresu czasu zanim uruchomisz pełny replay.

## 7. Notebooki

**Cel:** Delta tables i rekomendacje.

**Czynności:** Importować `01_load_dimensions.py`, `02_situation_index.py`, `03_escalation_recommendation.py`. Dodatkowo nazwij artefakt dokładnie jak w tej instrukcji, dodaj opis `COP-24 demo / dane syntetyczne` i ogranicz dostęp do zespołu demonstracyjnego.

**Oczekiwany rezultat:** Tabele `dim_*`, `kis_*`, `escalation_recommendations`.

**Orientacyjny czas:** 15 min.

**Kontrola:** po wykonaniu kroku zapisz zrzut lub notatkę w checklistcie demo. Jeśli krok dotyczy danych, użyj małego zakresu czasu zanim uruchomisz pełny replay.

## 8. Dashboard

**Cel:** Obraz operacyjny dla RCB/RZZK.

**Czynności:** Utworzyć `COP24_RTI_Dashboard` z pięcioma stronami. Dodatkowo nazwij artefakt dokładnie jak w tej instrukcji, dodaj opis `COP-24 demo / dane syntetyczne` i ogranicz dostęp do zespołu demonstracyjnego.

**Oczekiwany rezultat:** Kafelki odświeżają się.

**Orientacyjny czas:** 30 min.

**Kontrola:** po wykonaniu kroku zapisz zrzut lub notatkę w checklistcie demo. Jeśli krok dotyczy danych, użyj małego zakresu czasu zanim uruchomisz pełny replay.

## 9. Power BI

**Cel:** Warstwa decyzyjna i drill-down.

**Czynności:** Model wg `semantic-model/MODEL.md`, miary z `MEASURES.md`. Dodatkowo nazwij artefakt dokładnie jak w tej instrukcji, dodaj opis `COP-24 demo / dane syntetyczne` i ogranicz dostęp do zespołu demonstracyjnego.

**Oczekiwany rezultat:** Raport pokazuje KIS, ewakuacje, IK.

**Orientacyjny czas:** 30 min.

**Kontrola:** po wykonaniu kroku zapisz zrzut lub notatkę w checklistcie demo. Jeśli krok dotyczy danych, użyj małego zakresu czasu zanim uruchomisz pełny replay.

## 10. Activator

**Cel:** Alerty Teams/e-mail i SPO.

**Czynności:** Reguły z `activator/RULES.md`. Dodatkowo nazwij artefakt dokładnie jak w tej instrukcji, dodaj opis `COP-24 demo / dane syntetyczne` i ogranicz dostęp do zespołu demonstracyjnego.

**Oczekiwany rezultat:** Reguły testowe wyzwalają powiadomienia.

**Orientacyjny czas:** 20 min.

**Kontrola:** po wykonaniu kroku zapisz zrzut lub notatkę w checklistcie demo. Jeśli krok dotyczy danych, użyj małego zakresu czasu zanim uruchomisz pełny replay.

## 11. Data Agent

**Cel:** Odpowiedzi NL o sytuacji.

**Czynności:** Instrukcje `ai/DATA_AGENT.md`, źródła Eventhouse+Lakehouse. Dodatkowo nazwij artefakt dokładnie jak w tej instrukcji, dodaj opis `COP-24 demo / dane syntetyczne` i ogranicz dostęp do zespołu demonstracyjnego.

**Oczekiwany rezultat:** Agent cytuje liczby i ograniczenia.

**Orientacyjny czas:** 20 min.

**Kontrola:** po wykonaniu kroku zapisz zrzut lub notatkę w checklistcie demo. Jeśli krok dotyczy danych, użyj małego zakresu czasu zanim uruchomisz pełny replay.

## 12. Fabric App

**Cel:** Pulpit RZZK i write-back decyzji.

**Czynności:** Prompt `fabric-app/RAYFIN_PROMPT.md`. Dodatkowo nazwij artefakt dokładnie jak w tej instrukcji, dodaj opis `COP-24 demo / dane syntetyczne` i ogranicz dostęp do zespołu demonstracyjnego.

**Oczekiwany rezultat:** Aplikacja ma role, ekrany, rejestr.

**Orientacyjny czas:** 30 min.

**Kontrola:** po wykonaniu kroku zapisz zrzut lub notatkę w checklistcie demo. Jeśli krok dotyczy danych, użyj małego zakresu czasu zanim uruchomisz pełny replay.


## 📊 Konfiguracja stron dashboardu

1. `Obraz kraju` — KPI KIS, gminy w alarmie, ewakuowani, odbiorcy bez prądu.
2. `Hydrologia` — mapa wodowskazów, fala Kłodzko→Nysa→Opole→Wrocław.
3. `Infrastruktura krytyczna` — energia, telekom, korelacje.
4. `RZZK i SPO` — eskalacje i rekomendacje.
5. `Z20 Dezinformacja` — sygnały medialne, zasięg, kanały.

## ✅ Lista kontrolna „czy działa”

| # | Test | Wynik oczekiwany |
|---:|---|---|
| 1 | `python generate_datasets.py` | brak błędów i `datasets/README.md` |
| 2 | liczność hydro | `hydro_readings.jsonl` ma 449400 rekordów |
| 3 | dry-run symulatora | `DRY_RUN_SENT=25` |
| 4 | Eventstream input preview | widoczny JSON z `stream` |
| 5 | Eventhouse table count | tabele zwracają rekordy |
| 6 | `hydro_latest` | po jednym rekordzie na wodowskaz |
| 7 | `incidents_agg_15min` | agregacje 15-minutowe |
| 8 | Lakehouse dimensions | `dim_gmina` ma 2477 rekordów |
| 9 | notebook KIS | `kis_daily_country.csv` w `datasets/derived` |
| 10 | dashboard filters | działa filtr czasu i województwa |
| 11 | Activator | reguła stanu alarmowego generuje payload |
| 12 | Data Agent | odpowiada na pytanie o szczyt awarii zasilania |
| 13 | Fabric App | zapis testowej decyzji tworzy wpis audytowy |
| 14 | Plan B | lokalne pliki derived otwierają się bez Fabric |

## 🧯 Rozwiązywanie problemów

| Problem | Objaw | Przyczyna | Rozwiązanie |
|---|---|---|---|
| Błędne mapowanie JSON | kolumny null | mapping nie odpowiada polom JSON | uruchom ponownie `01_create_tables.kql`, sprawdź nazwy kolumn |
| Opóźnienie ingestii | dashboard pusty przez kilka minut | Eventstream batchuje | zmniejsz zakres, poczekaj, sprawdź metrics Eventstream |
| Limity Eventstream | throttling albo dropped events | zbyt szybki replay `--speed` | zmniejsz speed, dziel strumienie |
| Brak `azure-eventhub` | import error przy wysyłce | zależność nie zainstalowana | `--dry-run` działa bez zależności; do wysyłki użyj venv |
| Materialized view nie backfilluje | latest puste | brak danych w tabeli źródłowej | najpierw ingest, potem backfill lub odtwórz view |
| Data Agent halucynuje | odpowiedzi bez liczb | brak instrukcji systemowych | wklej `ai/DATA_AGENT.md` i ogranicz źródła |
| Power BI relacje many-to-many | duplikaty wyników | zły klucz geografii | użyj hierarchii woj→powiat→gmina |
