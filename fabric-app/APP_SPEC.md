# 🧩 Fabric App — „Pulpit RZZK”

> Aplikacja jest warstwą decyzyjną nad dashboardem. Dashboard odpowiada „co się dzieje?”, a Pulpit RZZK odpowiada „co robimy, kto zatwierdził i gdzie jest ślad audytowy?”.

## Role i uprawnienia

| Rola | Widok | Akcje | Ograniczenia |
|---|---|---|---|
| Dyrektor RCB | kraj, RZZK, audyt | zatwierdza rekomendacje, zwołuje RZZK, podpisuje brief | nie edytuje danych źródłowych |
| Oficer dyżurny | operacyjny, alerty | triage, przygotowanie briefu, projekt decyzji | decyzje jako wersje robocze |
| Wojewoda | własne województwo | wniosek o zasoby, status ewakuacji | brak dostępu do innych województw poza agregatem |
| Minister | kraj i resort | akceptacja SPO resortowych | brak modyfikacji wpisów innych resortów |

## Ekran 1 — Sytuacja krajowa

**Cel:** w 30 sekund pokazać, czy sytuacja wymaga rozmowy na poziomie RZZK. **Użytkownik:** Dyrektor RCB, minister, premier. **Wireframe:** górny pasek KPI; lewa mapa kraju; prawa lista top alertów; dół: trend KIS i oś eskalacji.

**Pola:** `kis_country:decimal(5,1)` wymagane; `max_local_kis:decimal`; `alarm_gminas:int`; `evacuated_people:int`; `customers_offline:int`; `disinfo_signals:int`; `last_refresh:datetime`. Walidacja: wartości ujemne niedozwolone, `last_refresh` nie starszy niż 15 minut w trybie online.

**Źródła:** `kis_country`, `kis_gmina`, `hydro_readings.level_cm`, `power_grid_events.customers_offline`, `media_signals.disinformation_flag`, `escalation_events`. **Akcje:** otwórz kartę województwa, wygeneruj brief, przejdź do SPO. **Write-back:** `brief_request` z parametrami filtra.

## Ekran 2 — Karta województwa

**Cel:** uzgodnić obraz między RCB i wojewodą. **Wireframe:** nagłówek województwa, mapa powiatów, tabela gmin, panele hydro/energia/telco/ewakuacja/zasoby. **Pola:** `voivodeship_code:string(2)` wymagane; `powiat_code:string(4)` opcjonalne; `gmina_code:string(7)` opcjonalne; `kis:decimal`; `psp_units:int`; `wot_soldiers:int`; `pumps:int`; `generators:int`; `helicopters:int`.

Walidacja: użytkownik z rolą wojewody może zapisać dane tylko dla swojego `voivodeship_code`. **Źródła:** `dim_voivodeship`, `dim_powiat`, `dim_gmina`, `resource_deployment`, `evacuation_status`, `power_grid_events`, `telecom_events`. **Akcje:** `request_resources`, `send_spo3_message`, `open_decision_form`.

## Ekran 3 — Rekomendowane SPO

**Cel:** zamienić alert w procedurę. **Wireframe:** lista kart SPO z kolorem statusu; po kliknięciu checklista; panel uzasadnienia. **Pola:** `spo_code:string`, `spo_name:string`, `owner_role:string`, `status:enum(draft,proposed,approved,done)`, `due_time:datetime`, `evidence:string`. **Walidacja:** `status=approved` wymaga roli Dyrektor RCB albo Minister.

**Źródła:** `dim_spo`, `escalation_recommendations`, `escalation_events`, `activator_alerts`. **Write-back:** `spo_action_log` z wersjonowaniem.

## Ekran 4 — Rejestr decyzji

**Cel:** audytowalność. **Wireframe:** tabela decyzji, filtr po SPO/obszarze, formularz dodania wersji. **Pola:** `decision_id:guid`, `timestamp:datetime`, `decision_maker:string`, `role:string`, `decision_text:string(4000)`, `scope:string`, `related_spo:string`, `source_alert:string`, `evidence_query:string`, `audit_hash:string`, `version:int`, `supersedes_decision_id:guid?`.

Walidacja: decyzji nie usuwa się; korekta tworzy nową wersję. `decision_text` wymagany min. 20 znaków. **Źródła:** write-back Lakehouse `decision_log`; referencje do Eventhouse. **Powiadomienia:** Teams do właścicieli SPO i e-mail do sekretariatu RZZK.

## Ekran 5 — Zwołaj RZZK (SPO-1)

**Cel:** skrócić czas od rekomendacji do formalnego działania. **Wireframe:** duży przycisk, lista uczestników, agenda, potwierdzenie, wynik wysyłki. **Pola:** `meeting_time`, `chair`, `participants`, `agenda_items`, `basis`, `teams_channel`, `email_distribution`. **Walidacja:** wymagana podstawa z `escalation_events` lub ręczne uzasadnienie dyrektora.

**Efekty:** wpis w `decision_log`, wpis w `spo_action_log`, wysłanie powiadomień, utworzenie briefu PDF/HTML, oznaczenie alertu jako `handled`.

## Model write-back

| Tabela | Klucz | Zastosowanie |
|---|---|---|
| `decision_log` | `decision_id, version` | nieusuwalny dziennik decyzji |
| `spo_action_log` | `action_id` | status checklist SPO |
| `brief_request` | `request_id` | żądania briefów |
| `notification_log` | `notification_id` | wynik Teams/e-mail |

## Przejścia i tryb offline

Każdy ekran ma link „pokaż dane źródłowe” do dashboardu/KQL. W trybie offline aplikacja używa ostatnich danych z `datasets/derived`, blokuje write-back produkcyjny i pozwala eksportować decyzje do pliku kolejki. Po powrocie online operator importuje kolejkę jako wersje decyzji z oznaczeniem `offline_created=true`.

## Obsługa błędów

Błąd źródła danych pokazuje banner, a nie pusty ekran. Brak uprawnień pokazuje komunikat z rolą wymaganą. Konflikt wersji decyzji wymusza utworzenie nowej wersji. Brak sieci przy powiadomieniu zapisuje `notification_log.status=failed` i proponuje ponowienie.

## Szczegółowe przejścia między ekranami

Z `Sytuacja krajowa` kliknięcie województwa otwiera `Karta województwa` z ustawionym `voivodeship_code`. Kliknięcie alertu z listy top alertów otwiera `Rekomendowane SPO` i filtruje do właściwego `source_alert`. Kliknięcie `Zwołaj RZZK` wymaga potwierdzenia i przenosi do formularza decyzji z automatycznie wypełnioną podstawą.

## Uprawnienia per pole

Dyrektor RCB może zatwierdzić `decision_log.status=approved` i uruchomić `notify_teams`. Oficer dyżurny może tworzyć `draft` i `proposed`, ale nie może zamknąć decyzji. Wojewoda może dodawać komentarze i wnioski zasobowe wyłącznie dla swojego województwa. Minister widzi rekomendacje powiązane z działem administracji i może oznaczyć działania resortowe jako zaakceptowane.

## Powiadomienia

Każde powiadomienie ma identyfikator, kanał, adresatów, treść, status wysyłki i link zwrotny do decyzji. Treść nie powinna zawierać danych wrażliwych; zawiera tylko kod obszaru, poziom ryzyka, SPO i link do bezpiecznego pulpitu. Nieudana wysyłka tworzy zadanie ponowienia dla oficera dyżurnego.

## Walidacje biznesowe

Nie można zwołać RZZK bez wskazania podstawy: alertu, rekomendacji albo ręcznego uzasadnienia dyrektora. Nie można oznaczyć ewakuacji jako zakończonej, jeśli liczba osób przekracza pojemność punktów przyjęcia bez komentarza. Nie można zamknąć SPO, jeśli checklista ma pozycje obowiązkowe bez statusu.

## Dostępność i użyteczność

Interfejs musi działać na dużym ekranie sali posiedzeń i na laptopie oficera. Karty KPI mają duże liczby, kolory i krótkie podpisy. Każda tabela ma eksport CSV, ale eksport decyzji wymaga roli z uprawnieniem audytowym. Wszystkie komunikaty błędów są po polsku i mówią, co zrobić dalej.

## Raportowanie statusu aplikacji

Aplikacja powinna mieć widoczny panel kondycji źródeł: Eventhouse, Lakehouse, Data Agent, powiadomienia i write-back. Dla każdego źródła pokaż `status`, `last_success`, `last_error` i link do instrukcji naprawy. Ten panel jest istotny w sali decyzyjnej, bo pozwala odróżnić realny brak zdarzeń od awarii integracji. Jeżeli źródło jest niedostępne, przy KPI pokaż znacznik „dane niepełne”, a w decyzji wymuś komentarz użytkownika, że decyzja została podjęta przy ograniczonej kompletności danych.
