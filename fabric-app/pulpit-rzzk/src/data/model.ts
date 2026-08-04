/**
 * Warstwa domenowa Pulpitu RZZK.
 *
 * Zrodlem danych sytuacyjnych jest statyczna scena (public/data/scene.json)
 * zbudowana skryptem tools/build_scene.py z katalogu datasets/ repozytorium.
 * Rayfin nie czyta Lakehouse ani Eventhouse, dlatego przez GraphQL idzie
 * wylacznie zapis zwrotny (decyzje, zadania SPO, briefy, powiadomienia).
 *
 * Wszystkie funkcje sa czyste - dzieki temu te same reguly, ktore widzi
 * uzytkownik, sa pokryte testami regresyjnymi.
 */

export interface SceneMeta {
  generatedAt: string;
  days: string[];
  d0: string;
  source: string;
  kisFormula: string;
  kisComponents: string[];
}

export interface Voivodeship {
  code: string;
  name: string;
  pop: number;
  seat: string;
  lat: number;
  lon: number;
}

export interface Gmina {
  code: string;
  name: string;
  v: string;
  powiat: string;
  pop: number;
  lat: number;
  lon: number;
}

export interface Gauge {
  id: string;
  name: string;
  river: string;
  g: string;
  warn: number;
  alarm: number;
  lat: number;
  lon: number;
  delayH: number;
}

export interface Hazard {
  code: string;
  name: string;
  lead: string;
  coop: string;
}

export interface Spo {
  code: string;
  name: string;
}

export interface Resources {
  psp_units?: number;
  wot_soldiers?: number;
  pumps?: number;
  generators?: number;
  helicopters?: number;
}

export interface CountryDay {
  d: string;
  kis: number;
  maxKis: number;
  over25: number;
  over45: number;
  over85: number;
  alarmGminas: number;
  warnGminas: number;
  inc: number;
  p1: number;
  aff: number;
  off: number;
  evac: number;
  minCov: number | null;
  covBelow50: number;
  media: number;
  disinfo: number;
  disinfoReach: number;
  negative: number;
  res: Resources;
  topTypes: [string, number][];
}

export interface VoivDay {
  d: string;
  v: string;
  kis: number;
  maxKis: number;
  alarmGminas: number;
  warnGminas: number;
  inc: number;
  p1: number;
  aff: number;
  off: number;
  evac: number;
  minCov: number | null;
  res: Resources;
  topTypes: [string, number][];
}

export interface GminaDay {
  d: string;
  g: string;
  kis: number;
  /** Wklad skladowych KIS: hydro, incydenty, energia, telekom, ewakuacja, zasoby. */
  c: number[];
  lvl: number;
  /** 1 = stan alarmowy, 2 = stan ostrzegawczy, 0 = ponizej progow. */
  alarm: number;
  inc: number;
  p1: number;
  aff: number;
  off: number;
  cov: number | null;
  evac: number;
  evs: string | null;
}

export interface GaugeDay {
  d: string;
  id: string;
  lvl: number;
  flow: number;
  trend: string;
  at: string;
}

export interface Escalation {
  ts: string;
  id: string;
  from: string;
  to: string;
  area: string;
  hazard: string;
  spo: string;
  reason: string;
}

export interface RecVoiv {
  d: string;
  v: string;
  maxKis: number;
  level: string;
  spo: string[];
  why: string;
}

export interface RecGmina {
  d: string;
  g: string;
  v: string;
  kis: number;
  level: string;
  spo: string[];
}

export interface MediaTopic {
  d: string;
  topic: string;
  count: number;
  reach: number;
  disinfo: number;
}

export interface Scene {
  meta: SceneMeta;
  voivodeships: Voivodeship[];
  gminas: Gmina[];
  gauges: Gauge[];
  hazards: Hazard[];
  spo: Spo[];
  country: CountryDay[];
  voivDaily: VoivDay[];
  gminaDaily: GminaDay[];
  gaugeDaily: GaugeDay[];
  escalations: Escalation[];
  recVoiv: RecVoiv[];
  recGmina: RecGmina[];
  mediaTopics: MediaTopic[];
}

/** Poziomy eskalacji uporzadkowane rosnaco - uzywane do porownan. */
export const ESCALATION_LEVELS = [
  'gmina',
  'powiat',
  'wojewoda',
  'minister wiodący',
  'RZZK',
] as const;

export type EscalationLevel = (typeof ESCALATION_LEVELS)[number];

export function levelRank(level: string): number {
  const i = ESCALATION_LEVELS.indexOf(level as EscalationLevel);
  return i < 0 ? 0 : i;
}

/**
 * Progi rekomendacji sa te same co w notebooks/03_escalation_recommendation.py.
 * Duplikacja jest swiadoma, ale musi byc pokryta testem, zeby aplikacja i Lakehouse
 * nie pokazywaly roznych rekomendacji dla tej samej wartosci KIS.
 */
export function recommendLevel(kis: number): { level: EscalationLevel; spo: string[] } {
  if (kis >= 85) return { level: 'RZZK', spo: ['SPO-1', 'SPO-2', 'SPO-3', 'SPO-10'] };
  if (kis >= 65) return { level: 'minister wiodący', spo: ['SPO-12', 'SPO-3'] };
  if (kis >= 45) return { level: 'wojewoda', spo: ['SPO-3', 'SPO-12'] };
  if (kis >= 25) return { level: 'powiat', spo: ['SPO-3', 'SPO-12'] };
  return { level: 'gmina', spo: ['SPO-3'] };
}

export interface SceneIndex {
  scene: Scene;
  days: string[];
  voivByCode: Map<string, Voivodeship>;
  gminaByCode: Map<string, Gmina>;
  gaugeById: Map<string, Gauge>;
  spoByCode: Map<string, Spo>;
  hazardByCode: Map<string, Hazard>;
  countryByDay: Map<string, CountryDay>;
  voivByDay: Map<string, VoivDay[]>;
  gminaByDay: Map<string, GminaDay[]>;
  gaugeByDay: Map<string, GaugeDay[]>;
  mediaByDay: Map<string, MediaTopic[]>;
}

function group<T>(rows: T[], key: (row: T) => string): Map<string, T[]> {
  const out = new Map<string, T[]>();
  for (const row of rows) {
    const k = key(row);
    const arr = out.get(k);
    if (arr) arr.push(row);
    else out.set(k, [row]);
  }
  return out;
}

export function indexScene(scene: Scene): SceneIndex {
  return {
    scene,
    days: scene.meta.days,
    voivByCode: new Map(scene.voivodeships.map((v) => [v.code, v])),
    gminaByCode: new Map(scene.gminas.map((g) => [g.code, g])),
    gaugeById: new Map(scene.gauges.map((g) => [g.id, g])),
    spoByCode: new Map(scene.spo.map((s) => [s.code, s])),
    hazardByCode: new Map(scene.hazards.map((h) => [h.code, h])),
    countryByDay: new Map(scene.country.map((c) => [c.d, c])),
    voivByDay: group(scene.voivDaily, (r) => r.d),
    gminaByDay: group(scene.gminaDaily, (r) => r.d),
    gaugeByDay: group(scene.gaugeDaily, (r) => r.d),
    mediaByDay: group(scene.mediaTopics, (r) => r.d),
  };
}

/** Wartosc dnia poprzedniego - do liczenia delty w kafelkach KPI. */
export function previousDay(index: SceneIndex, day: string): CountryDay | null {
  const i = index.days.indexOf(day);
  if (i <= 0) return null;
  return index.countryByDay.get(index.days[i - 1]) ?? null;
}

export interface Kpi {
  key: string;
  label: string;
  value: number;
  prev: number | null;
  unit?: string;
  hint: string;
  /** true = wzrost jest zly (czerwony), false = wzrost jest dobry. */
  higherIsWorse: boolean;
}

export function countryKpis(index: SceneIndex, day: string): Kpi[] {
  const c = index.countryByDay.get(day);
  const p = previousDay(index, day);
  if (!c) return [];
  return [
    {
      key: 'kis',
      label: 'KIS krajowy',
      value: c.kis,
      prev: p?.kis ?? null,
      hint: 'Średnia z gmin, skala 0–100.',
      higherIsWorse: true,
    },
    {
      key: 'maxKis',
      label: 'Maks. lokalny KIS',
      value: c.maxKis,
      prev: p?.maxKis ?? null,
      hint: 'Najwyższa wartość w pojedynczej gminie.',
      higherIsWorse: true,
    },
    {
      key: 'alarm',
      label: 'Gminy w stanie alarmowym',
      value: c.alarmGminas,
      prev: p?.alarmGminas ?? null,
      hint: 'Przekroczony stan alarmowy na wodowskazie.',
      higherIsWorse: true,
    },
    {
      key: 'evac',
      label: 'Osoby objęte ewakuacją',
      value: c.evac,
      prev: p?.evac ?? null,
      hint: 'Suma najwyższych stanów ewakuacji w gminach.',
      higherIsWorse: true,
    },
    {
      key: 'off',
      label: 'Odbiorcy bez zasilania',
      value: c.off,
      prev: p?.off ?? null,
      hint: 'Suma zdarzeń sieciowych z dnia.',
      higherIsWorse: true,
    },
    {
      key: 'inc',
      label: 'Zgłoszenia 112 / PSP',
      value: c.inc,
      prev: p?.inc ?? null,
      hint: 'Liczba incydentów zarejestrowanych w dniu.',
      higherIsWorse: true,
    },
    {
      key: 'disinfo',
      label: 'Sygnały dezinformacji',
      value: c.disinfo,
      prev: p?.disinfo ?? null,
      hint: 'Wpisy oznaczone jako dezinformacja.',
      higherIsWorse: true,
    },
    {
      key: 'cov',
      label: 'Min. pokrycie telekom.',
      value: c.minCov ?? 100,
      prev: p?.minCov ?? null,
      unit: '%',
      hint: 'Najgorsze pokrycie w gminie — ryzyko utraty alarmowania.',
      higherIsWorse: false,
    },
  ];
}

export interface VoivRow extends VoivDay {
  name: string;
  seat: string;
  pop: number;
  rec: { level: EscalationLevel; spo: string[] };
  /** Zmiana KIS wzgledem dnia poprzedniego. */
  delta: number | null;
}

export function voivodeshipRows(index: SceneIndex, day: string): VoivRow[] {
  const prevIdx = index.days.indexOf(day) - 1;
  const prev = prevIdx >= 0 ? index.voivByDay.get(index.days[prevIdx]) ?? [] : [];
  const prevByCode = new Map(prev.map((r) => [r.v, r]));
  const rows = index.voivByDay.get(day) ?? [];
  return rows
    .map((r) => {
      const v = index.voivByCode.get(r.v);
      const before = prevByCode.get(r.v);
      return {
        ...r,
        name: v?.name ?? r.v,
        seat: v?.seat ?? '',
        pop: v?.pop ?? 0,
        rec: recommendLevel(r.maxKis),
        delta: before ? Math.round((r.kis - before.kis) * 10) / 10 : null,
      };
    })
    .sort((a, b) => b.maxKis - a.maxKis || a.name.localeCompare(b.name, 'pl'));
}

export interface GminaRow extends GminaDay {
  name: string;
  v: string;
  vName: string;
  powiat: string;
  pop: number;
  lat: number;
  lon: number;
  rec: { level: EscalationLevel; spo: string[] };
}

export function gminaRows(index: SceneIndex, day: string, voivCode?: string): GminaRow[] {
  const rows = index.gminaByDay.get(day) ?? [];
  const out: GminaRow[] = [];
  for (const r of rows) {
    const g = index.gminaByCode.get(r.g);
    if (!g) continue;
    if (voivCode && g.v !== voivCode) continue;
    out.push({
      ...r,
      name: g.name,
      v: g.v,
      vName: index.voivByCode.get(g.v)?.name ?? g.v,
      powiat: g.powiat,
      pop: g.pop,
      lat: g.lat,
      lon: g.lon,
      rec: recommendLevel(r.kis),
    });
  }
  return out.sort((a, b) => b.kis - a.kis || a.name.localeCompare(b.name, 'pl'));
}

/** Przebieg wartosci w calej scenie - do wykresow przebiegu. */
export function countrySeries(index: SceneIndex, field: keyof CountryDay): number[] {
  return index.scene.country.map((c) => {
    const v = c[field];
    return typeof v === 'number' ? v : 0;
  });
}

export function voivSeries(index: SceneIndex, voivCode: string, field: keyof VoivDay): number[] {
  return index.days.map((d) => {
    const row = (index.voivByDay.get(d) ?? []).find((r) => r.v === voivCode);
    const v = row ? row[field] : 0;
    return typeof v === 'number' ? v : 0;
  });
}

/**
 * Propagacja fali: dla wskazanego dnia zwraca wodowskazy powyzej progow
 * wraz z wyprzedzeniem czasowym wzgledem profilu najwyzej polozonego.
 */
export interface WaveStep {
  gaugeId: string;
  gaugeName: string;
  river: string;
  gminaName: string;
  level: number;
  alarm: number;
  warn: number;
  trend: string;
  etaHours: number;
  state: 'alarm' | 'ostrzegawczy';
}

export function wavePropagation(index: SceneIndex, day: string): WaveStep[] {
  const rows = index.gaugeByDay.get(day) ?? [];
  const base = Math.min(...index.scene.gauges.map((g) => g.delayH));
  const out: WaveStep[] = [];
  for (const r of rows) {
    const g = index.gaugeById.get(r.id);
    if (!g) continue;
    if (r.lvl < g.warn) continue;
    out.push({
      gaugeId: g.id,
      gaugeName: g.name,
      river: g.river,
      gminaName: index.gminaByCode.get(g.g)?.name ?? g.g,
      level: r.lvl,
      alarm: g.alarm,
      warn: g.warn,
      trend: r.trend,
      etaHours: Math.round(g.delayH - base),
      state: r.lvl >= g.alarm ? 'alarm' : 'ostrzegawczy',
    });
  }
  return out.sort((a, b) => a.etaHours - b.etaHours || b.level - a.level).slice(0, 12);
}

/** Skladowe KIS gminy rozpisane na nazwy - panel wyjasnialnosci. */
export function kisBreakdown(index: SceneIndex, row: GminaDay): { label: string; value: number }[] {
  return index.scene.meta.kisComponents.map((label, i) => ({
    label,
    value: row.c[i] ?? 0,
  }));
}

/**
 * Kaskada infrastruktury: czy wystepuja jednoczesnie skutki w wodzie, energii,
 * lacznosci i ewakuacji. To przeslanka do RZZK, bo problem przestaje byc
 * jednoresortowy.
 */
export interface CascadeSignal {
  key: string;
  label: string;
  active: boolean;
  detail: string;
}

export function cascadeSignals(row: VoivDay | CountryDay): CascadeSignal[] {
  return [
    {
      key: 'hydro',
      label: 'Zagrożenie hydrologiczne',
      active: row.alarmGminas > 0,
      detail: `${row.alarmGminas} gmin w stanie alarmowym`,
    },
    {
      key: 'power',
      label: 'Energetyka',
      active: row.off > 5000,
      detail: `${row.off.toLocaleString('pl-PL')} odbiorców bez zasilania`,
    },
    {
      key: 'telecom',
      label: 'Łączność',
      active: row.minCov !== null && row.minCov < 50,
      detail: row.minCov === null ? 'brak zdarzeń' : `min. pokrycie ${row.minCov}%`,
    },
    {
      key: 'evac',
      label: 'Ewakuacja ludności',
      active: row.evac > 1000,
      detail: `${row.evac.toLocaleString('pl-PL')} osób`,
    },
  ];
}

export function cascadeCount(row: VoivDay | CountryDay): number {
  return cascadeSignals(row).filter((s) => s.active).length;
}

/**
 * Przeslanka zwolania RZZK. Rekomendacja algorytmiczna opiera sie na KIS,
 * ale wieloresortowa kaskada jest osobnym argumentem - decyzje podejmuje czlowiek.
 */
export interface RzzkCase {
  day: string;
  recommendedLevel: EscalationLevel;
  maxKis: number;
  cascade: number;
  affectedVoivodeships: string[];
  pros: string[];
  cons: string[];
  suggestSummon: boolean;
}

export function rzzkCase(index: SceneIndex, day: string): RzzkCase {
  const c = index.countryByDay.get(day);
  const rows = voivodeshipRows(index, day);
  const hot = rows.filter((r) => r.maxKis >= 45);
  const rec = recommendLevel(c?.maxKis ?? 0);
  const cascade = c ? cascadeCount(c) : 0;
  const pros: string[] = [];
  const cons: string[] = [];

  if (c) {
    if (c.maxKis >= 45) pros.push(`Maks. lokalny KIS ${c.maxKis} przekracza próg wojewódzki (45).`);
    if (hot.length >= 2)
      pros.push(`Zagrożenie obejmuje ${hot.length} województwa: ${hot.map((r) => r.name).join(', ')}.`);
    if (cascade >= 3)
      pros.push(`Kaskada wieloresortowa: ${cascade} z 4 obszarów naraz (woda, energia, łączność, ewakuacja).`);
    if (c.evac >= 1000) pros.push(`Ewakuacja obejmuje ${c.evac.toLocaleString('pl-PL')} osób.`);
    if (c.disinfo >= 30)
      pros.push(`${c.disinfo} sygnałów dezinformacji — ryzyko dla skuteczności komunikatów.`);
    if (c.minCov !== null && c.minCov < 50)
      pros.push(`Pokrycie telekomunikacyjne spada do ${c.minCov}% — zagrożone alarmowanie ludności.`);

    if (c.maxKis < 65) cons.push('Rekomendacja algorytmiczna nie osiąga progu ministra wiodącego (65).');
    if (hot.length <= 1)
      cons.push('Zagrożenie skoncentrowane w jednym województwie — możliwe działanie na poziomie wojewody.');
    if (c.p1 === 0) cons.push('Brak zgłoszeń o priorytecie 1 w tym dniu.');
  }

  return {
    day,
    recommendedLevel: rec.level,
    maxKis: c?.maxKis ?? 0,
    cascade,
    affectedVoivodeships: hot.map((r) => r.name),
    pros,
    cons,
    suggestSummon: (c?.maxKis ?? 0) >= 45 && cascade >= 3 && hot.length >= 2,
  };
}

/** Projekcja mapy: prosty rzut rownoprostokatny wystarcza dla Polski. */
export function project(
  lat: number,
  lon: number,
  box = { minLat: 49.0, maxLat: 54.9, minLon: 14.1, maxLon: 24.2 },
  size = { w: 100, h: 100 }
): { x: number; y: number } {
  return {
    x: ((lon - box.minLon) / (box.maxLon - box.minLon)) * size.w,
    y: ((box.maxLat - lat) / (box.maxLat - box.minLat)) * size.h,
  };
}

export function kisColor(kis: number): string {
  if (kis >= 65) return '#dc2626';
  if (kis >= 45) return '#f97316';
  if (kis >= 25) return '#facc15';
  if (kis >= 10) return '#38bdf8';
  return '#22d3ee';
}

export function levelBadgeClass(level: string): string {
  switch (level) {
    case 'RZZK':
      return 'bg-red-500/15 text-red-300 ring-red-500/40';
    case 'minister wiodący':
      return 'bg-orange-500/15 text-orange-300 ring-orange-500/40';
    case 'wojewoda':
      return 'bg-amber-500/15 text-amber-300 ring-amber-500/40';
    case 'powiat':
      return 'bg-sky-500/15 text-sky-300 ring-sky-500/40';
    default:
      return 'bg-slate-500/15 text-slate-300 ring-slate-500/40';
  }
}

export function formatNumber(n: number): string {
  return n.toLocaleString('pl-PL');
}

export function formatDay(day: string, d0: string): string {
  const date = new Date(`${day}T12:00:00Z`);
  const zero = new Date(`${d0}T12:00:00Z`);
  const diff = Math.round((date.getTime() - zero.getTime()) / 86400000);
  const rel = diff === 0 ? 'D0' : diff > 0 ? `D+${diff}` : `D${diff}`;
  const label = date.toLocaleDateString('pl-PL', { day: '2-digit', month: 'short' });
  return `${label} · ${rel}`;
}

/** Skrot kontrolny przeslanek - slad audytowy decyzji. */
export function auditHash(payload: string): string {
  let h1 = 0x811c9dc5;
  let h2 = 0x01000193;
  for (let i = 0; i < payload.length; i++) {
    const ch = payload.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 0x01000193) >>> 0;
    h2 = Math.imul(h2 + ch + i, 0x85ebca6b) >>> 0;
  }
  return h1.toString(16).padStart(8, '0') + h2.toString(16).padStart(8, '0');
}

export function toCsv(rows: Record<string, unknown>[]): string {
  if (rows.length === 0) return '';
  const cols = Object.keys(rows[0]);
  const esc = (v: unknown) => {
    const s = v === null || v === undefined ? '' : String(v);
    return /[";\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return (
    '\ufeff' + [cols.join(';'), ...rows.map((r) => cols.map((c) => esc(r[c])).join(';'))].join('\n')
  );
}
