import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  auditHash,
  cascadeCount,
  countryKpis,
  gminaRows,
  indexScene,
  kisBreakdown,
  levelRank,
  recommendLevel,
  rzzkCase,
  toCsv,
  voivodeshipRows,
  wavePropagation,
  type Scene,
} from '@/data/model';
import { validateDecision, type Actor, type DecisionDraft } from '@/services/decisions';

const scene = JSON.parse(
  readFileSync(resolve(__dirname, '../../public/data/scene.json'), 'utf-8')
) as Scene;
const index = indexScene(scene);

/** Doba kulminacji w scenie - wyliczona, nie wpisana na sztywno. */
const peakDay = scene.country.reduce((a, b) => (b.maxKis > a.maxKis ? b : a)).d;

describe('scena', () => {
  it('obejmuje 14 dob od 2026-09-12 do 2026-09-25', () => {
    expect(scene.meta.days).toHaveLength(14);
    expect(scene.meta.days[0]).toBe('2026-09-12');
    expect(scene.meta.days[13]).toBe('2026-09-25');
  });

  it('ma komplet 16 wojewodztw w kazdej dobie', () => {
    for (const day of scene.meta.days) {
      expect(index.voivByDay.get(day)).toHaveLength(16);
    }
  });

  it('zawiera dokladnie 10 gmin, ktore osiagnely stan alarmowy', () => {
    const alarmed = new Set<string>();
    for (const row of scene.gminaDaily) if (row.alarm === 1) alarmed.add(row.g);
    expect(alarmed.size).toBe(10);
  });

  it('kulminacja wypada w scenie i osiaga prog zwolania RZZK', () => {
    expect(scene.meta.days).toContain(peakDay);
    const peak = index.countryByDay.get(peakDay)!;
    expect(peak.maxKis).toBeGreaterThanOrEqual(85);
  });

  it('prog RZZK jest przekraczany punktowo, a nie w polowie sceny', () => {
    const overRzzk = scene.country.filter((c) => c.maxKis >= 85);
    expect(overRzzk.length).toBeGreaterThanOrEqual(1);
    expect(overRzzk.length).toBeLessThanOrEqual(3);
  });

  it('KIS krajowy nigdy nie przekracza maksimum lokalnego', () => {
    for (const c of scene.country) expect(c.kis).toBeLessThanOrEqual(c.maxKis);
  });
});

describe('rekomendacja poziomu', () => {
  it('odwzorowuje progi z notatnika 03', () => {
    expect(recommendLevel(0).level).toBe('gmina');
    expect(recommendLevel(24.9).level).toBe('gmina');
    expect(recommendLevel(25).level).toBe('powiat');
    expect(recommendLevel(44.9).level).toBe('powiat');
    expect(recommendLevel(45).level).toBe('wojewoda');
    expect(recommendLevel(65).level).toBe('minister wiodący');
    expect(recommendLevel(85).level).toBe('RZZK');
    expect(recommendLevel(100).spo).toContain('SPO-1');
  });

  it('porzadkuje poziomy rosnaco', () => {
    expect(levelRank('gmina')).toBeLessThan(levelRank('powiat'));
    expect(levelRank('wojewoda')).toBeLessThan(levelRank('RZZK'));
  });

  it('kazde wojewodztwo w kulminacji ma rekomendacje zgodna z maks. KIS', () => {
    for (const row of voivodeshipRows(index, peakDay)) {
      expect(row.rec.level).toBe(recommendLevel(row.maxKis).level);
    }
  });
});

describe('wskazniki', () => {
  it('zwraca osiem kafelkow z delta wzgledem doby poprzedniej', () => {
    const kpis = countryKpis(index, scene.meta.days[5]);
    expect(kpis).toHaveLength(8);
    expect(kpis.every((k) => k.prev !== null)).toBe(true);
  });

  it('pierwsza doba nie ma wartosci porownawczej', () => {
    const kpis = countryKpis(index, scene.meta.days[0]);
    expect(kpis.every((k) => k.prev === null)).toBe(true);
  });

  it('pokrycie telekomunikacyjne traktuje spadek jako pogorszenie', () => {
    const cov = countryKpis(index, peakDay).find((k) => k.key === 'cov');
    expect(cov?.higherIsWorse).toBe(false);
  });
});

describe('skladowe KIS', () => {
  it('sumuja sie do wartosci indeksu (albo do 100 przy obcieciu)', () => {
    for (const row of gminaRows(index, peakDay).slice(0, 40)) {
      const sum = kisBreakdown(index, row).reduce((a, b) => a + b.value, 0);
      expect(Math.abs(Math.min(sum, 100) - row.kis)).toBeLessThan(0.6);
    }
  });

  it('ma szesc skladowych o nazwach z metadanych sceny', () => {
    const row = gminaRows(index, peakDay)[0];
    expect(kisBreakdown(index, row)).toHaveLength(6);
    expect(kisBreakdown(index, row)[0].label).toBe('hydrologia');
  });
});

describe('propagacja fali', () => {
  it('zwraca wylacznie wodowskazy powyzej stanu ostrzegawczego', () => {
    for (const step of wavePropagation(index, peakDay)) {
      expect(step.level).toBeGreaterThanOrEqual(step.warn);
      expect(['alarm', 'ostrzegawczy']).toContain(step.state);
    }
  });

  it('sortuje wg wyprzedzenia czasowego i ogranicza liste do 12 pozycji', () => {
    const steps = wavePropagation(index, peakDay);
    expect(steps.length).toBeLessThanOrEqual(12);
    for (let i = 1; i < steps.length; i++) {
      expect(steps[i].etaHours).toBeGreaterThanOrEqual(steps[i - 1].etaHours);
    }
  });
});

describe('przeslanki RZZK', () => {
  it('w kulminacji wykrywa kaskade wieloresortowa', () => {
    const c = index.countryByDay.get(peakDay)!;
    expect(cascadeCount(c)).toBeGreaterThanOrEqual(3);
  });

  it('zestawia argumenty za i przeciw', () => {
    const kase = rzzkCase(index, peakDay);
    expect(kase.pros.length).toBeGreaterThan(0);
    expect(kase.maxKis).toBe(index.countryByDay.get(peakDay)!.maxKis);
  });

  it('w pierwszej dobie nie sugeruje zwolania', () => {
    expect(rzzkCase(index, scene.meta.days[0]).suggestSummon).toBe(false);
  });
});

const actor = (role: Actor['role'], voiv = ''): Actor => ({
  id: 'u1',
  name: 'Test',
  role,
  voivodeshipCode: voiv,
});

const draft = (over: Partial<DecisionDraft> = {}): DecisionDraft => ({
  scene_day: peakDay,
  scope: 'województwo',
  voivodeship_code: '02',
  title: 'Reagowanie',
  decision_text: 'Uruchamiam procedury SPO i podnoszę poziom reagowania do wojewódzkiego.',
  recommended_level: 'wojewoda',
  chosen_level: 'wojewoda',
  spo_codes: ['SPO-3'],
  status: 'projekt',
  kis_at_decision: 50,
  evidence: { kis: 50 },
  ...over,
});

describe('walidacja decyzji', () => {
  it('przyjmuje poprawny projekt', () => {
    expect(validateDecision(draft(), actor('Dyrektor RCB')).ok).toBe(true);
  });

  it('wymaga co najmniej 20 znakow tresci', () => {
    const res = validateDecision(draft({ decision_text: 'za krótko' }), actor('Dyrektor RCB'));
    expect(res.ok).toBe(false);
    expect(res.errors.join()).toContain('20 znaków');
  });

  it('nie pozwala oficerowi dyzurnemu zatwierdzic decyzji', () => {
    const res = validateDecision(draft({ status: 'zatwierdzona' }), actor('oficer dyżurny'));
    expect(res.ok).toBe(false);
  });

  it('pozwala zatwierdzic Dyrektorowi RCB i ministrowi wiodacemu', () => {
    expect(validateDecision(draft({ status: 'zatwierdzona' }), actor('Dyrektor RCB')).ok).toBe(true);
    expect(
      validateDecision(draft({ status: 'zatwierdzona' }), actor('minister wiodący')).ok
    ).toBe(true);
  });

  it('blokuje wojewode poza wlasnym wojewodztwem', () => {
    const res = validateDecision(draft({ voivodeship_code: '14' }), actor('wojewoda', '02'));
    expect(res.ok).toBe(false);
    expect(res.errors.join()).toContain('własnego województwa');
  });

  it('blokuje wojewode przy zakresie krajowym', () => {
    const res = validateDecision(
      draft({ scope: 'kraj', voivodeship_code: '' }),
      actor('wojewoda', '02')
    );
    expect(res.ok).toBe(false);
  });

  it('wymaga wskazania co najmniej jednej procedury SPO', () => {
    expect(validateDecision(draft({ spo_codes: [] }), actor('Dyrektor RCB')).ok).toBe(false);
  });
});

describe('slad audytowy', () => {
  it('jest stabilny dla tych samych przeslanek', () => {
    expect(auditHash('abc')).toBe(auditHash('abc'));
  });

  it('zmienia sie przy zmianie przeslanek', () => {
    expect(auditHash('abc')).not.toBe(auditHash('abd'));
  });

  it('ma stala dlugosc 16 znakow', () => {
    expect(auditHash('dowolne przesłanki 2026')).toHaveLength(16);
  });
});

describe('eksport CSV', () => {
  it('dodaje BOM i uzywa srednika jako separatora', () => {
    const csv = toCsv([{ a: 1, b: 'test' }]);
    expect(csv.startsWith('\ufeff')).toBe(true);
    expect(csv).toContain('a;b');
  });

  it('cytuje wartosci ze srednikiem', () => {
    expect(toCsv([{ a: 'x;y' }])).toContain('"x;y"');
  });
});
