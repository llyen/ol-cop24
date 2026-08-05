import { useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';

import {
  formatNumber,
  gminaRows,
  levelBadgeClass,
  levelRank,
  voivodeshipRows,
} from '@/data/model';
import { useScenario } from '@/hooks/ScenarioContext';
import { DecisionForm } from '@/components/DecisionForm';
import { Badge, Button, EmptyState, Panel, Toast } from '@/components/ui';

/**
 * Ekran 3: rekomendowane procedury SPO.
 *
 * Rekomendacja jest liczona z KIS wg progow z notatnika 03. Ekran ma pokazac,
 * ze system nie decyduje - podaje propozycje razem z uzasadnieniem,
 * a czlowiek moze ja przyjac, podniesc albo obnizyc.
 */
export function RecommendationsPage() {
  const { index, day, refresh } = useScenario();
  const [params] = useSearchParams();
  const [openFor, setOpenFor] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  const rows = useMemo(() => (index ? voivodeshipRows(index, day) : []), [index, day]);
  const focus = params.get('v');

  if (!index) return <EmptyState text="Wczytywanie sceny…" />;

  const actionable = rows.filter((r) => r.maxKis >= 25);
  const quiet = rows.filter((r) => r.maxKis < 25);
  const ordered = focus
    ? [...actionable].sort((a, b) => (a.v === focus ? -1 : b.v === focus ? 1 : 0))
    : actionable;

  return (
    <div className="space-y-4">
      <Panel
        title="Jak powstaje rekomendacja"
        subtitle="progi te same, co w notatniku 03 w Lakehouse"
        tone="accent"
      >
        <div className="grid gap-2 text-xs sm:grid-cols-5">
          {[
            ['< 25', 'gmina'],
            ['≥ 25', 'powiat'],
            ['≥ 45', 'wojewoda'],
            ['≥ 65', 'minister wiodący'],
            ['≥ 85', 'RZZK'],
          ].map(([range, level]) => (
            <div key={level} className="rounded-lg bg-slate-50 px-3 py-2 ring-1 ring-slate-200">
              <div className="tabular-nums text-slate-500">maks. lokalny KIS {range}</div>
              <div className="mt-0.5">
                <Badge className={levelBadgeClass(level)}>{level}</Badge>
              </div>
            </div>
          ))}
        </div>
      </Panel>

      {ordered.length === 0 ? (
        <EmptyState text="W tej dobie żadne województwo nie przekracza progu powiatowego (KIS 25)." />
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {ordered.map((r) => {
            const gminas = gminaRows(index, day, r.v).filter((g) => g.kis >= 25);
            const escalated = index.scene.escalations.filter(
              (e) => e.ts.slice(0, 10) <= day && gminas.some((g) => g.name === e.area)
            );
            return (
              <Panel
                key={r.v}
                title={r.name}
                subtitle={`maks. lokalny KIS ${r.maxKis} · ${gminas.length} gmin powyżej progu`}
                tone={levelRank(r.rec.level) >= 3 ? 'alert' : 'default'}
                right={<Badge className={levelBadgeClass(r.rec.level)}>{r.rec.level}</Badge>}
              >
                <div className="space-y-3">
                  <div className="rounded-lg bg-slate-50 px-3 py-2 text-xs text-slate-700">
                    Przesłanki: {r.alarmGminas} gmin w stanie alarmowym · {r.inc} zgłoszeń (P1:{' '}
                    {r.p1}) · {formatNumber(r.off)} odbiorców bez zasilania ·{' '}
                    {formatNumber(r.evac)} ewakuowanych
                    {r.minCov !== null ? ` · min. pokrycie ${r.minCov}%` : ''}
                  </div>

                  <div>
                    <p className="mb-1.5 text-[11px] uppercase tracking-wide text-slate-500">
                      Proponowane procedury
                    </p>
                    <ul className="space-y-1">
                      {r.rec.spo.map((code) => (
                        <li
                          key={code}
                          className="rounded-lg bg-slate-50 px-3 py-1.5 text-sm text-slate-900"
                        >
                          <span className="font-medium text-gov">{code}</span>{' '}
                          <span className="text-xs text-slate-500">
                            {index.spoByCode.get(code)?.name ?? ''}
                          </span>
                        </li>
                      ))}
                    </ul>
                  </div>

                  {gminas.length > 0 && (
                    <div>
                      <p className="mb-1.5 text-[11px] uppercase tracking-wide text-slate-500">
                        Gminy wymagające uwagi
                      </p>
                      <div className="flex flex-wrap gap-1.5">
                        {gminas.slice(0, 12).map((g) => (
                          <Badge key={g.g} className={levelBadgeClass(g.rec.level)}>
                            {g.name} · {g.kis}
                          </Badge>
                        ))}
                      </div>
                    </div>
                  )}

                  {escalated.length > 0 && (
                    <div className="rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800 ring-1 ring-amber-600/30">
                      Zarejestrowana eskalacja: {escalated[0].from} → {escalated[0].to} ({escalated[0].area}).{' '}
                      {escalated[0].reason}
                    </div>
                  )}

                  <div className="flex justify-end">
                    <Button variant="primary" onClick={() => setOpenFor(r.v)}>
                      Zapisz decyzję
                    </Button>
                  </div>
                </div>

                {openFor === r.v && (
                  <DecisionForm
                    open
                    onClose={() => setOpenFor(null)}
                    onSaved={(rec) => {
                      setToast(`Zapisano decyzję ${rec.decision_id} (wersja ${rec.version}).`);
                      void refresh();
                    }}
                    day={day}
                    scope="województwo"
                    voivodeshipCode={r.v}
                    recommendedLevel={r.rec.level}
                    recommendedSpo={r.rec.spo}
                    kis={r.maxKis}
                    defaultTitle={`Reagowanie — ${r.name}, doba ${day}`}
                  />
                )}
              </Panel>
            );
          })}
        </div>
      )}

      {quiet.length > 0 && (
        <Panel title="Pozostałe województwa" subtitle="poniżej progu powiatowego">
          <div className="flex flex-wrap gap-1.5">
            {quiet.map((r) => (
              <Badge key={r.v} className="bg-slate-100 text-slate-600 ring-slate-300">
                {r.name} · {r.maxKis}
              </Badge>
            ))}
          </div>
        </Panel>
      )}

      <Toast message={toast} onDone={() => setToast(null)} />
    </div>
  );
}
