import { entity, role, text, int, decimal, date, uuid } from '@microsoft/rayfin-core';

/**
 * Rejestr decyzji COP-24.
 *
 * Zasada z APP_SPEC.md: decyzji nie usuwa sie. Zmiana = nowy wiersz z tym samym
 * decision_id, wyzszym numerem wersji i wypelnionym supersedes_version.
 * Dlatego encja nie ma roli z akcja 'delete', a aktualizacje sa dozwolone
 * wylacznie dla autora wpisu (np. korekta literowki przed zatwierdzeniem).
 */
@entity()
@role('authenticated', ['create', 'read'])
@role('authenticated', ['update'], {
  policy: (claims, item) => claims.sub.eq(item.author_id),
})
export class DecisionLog {
  @uuid() id!: string;
  /** Stabilny identyfikator decyzji, wspolny dla wszystkich wersji. */
  @text({ min: 3, max: 40 }) decision_id!: string;
  @int() version!: number;
  /** Numer wersji, ktora ten wpis zastepuje. 0 = pierwsza wersja. */
  @int() supersedes_version!: number;
  /** Dzien sceny, ktorego dotyczy decyzja (YYYY-MM-DD). */
  @text({ min: 10, max: 10 }) scene_day!: string;
  /** 'kraj' albo 'wojewodztwo'. */
  @text({ min: 4, max: 20 }) scope!: string;
  @text({ max: 4 }) voivodeship_code!: string;
  @text({ min: 3, max: 160 }) title!: string;
  @text({ min: 20, max: 2000 }) decision_text!: string;
  @text({ max: 30 }) recommended_level!: string;
  @text({ min: 3, max: 30 }) chosen_level!: string;
  @text({ max: 200 }) spo_codes!: string;
  /** 'projekt' | 'zatwierdzona' | 'odrzucona' | 'wycofana'. */
  @text({ min: 3, max: 20 }) status!: string;
  @decimal() kis_at_decision!: number;
  /** Migawka przeslanek (JSON) - co decydent widzial w chwili decyzji. */
  @text({ max: 2000 }) evidence!: string;
  @text({ max: 64 }) audit_hash!: string;
  @text({ max: 120 }) author_id!: string;
  @text({ max: 160 }) author_name!: string;
  @text({ min: 3, max: 40 }) author_role!: string;
  @date() created_at!: Date;
}
