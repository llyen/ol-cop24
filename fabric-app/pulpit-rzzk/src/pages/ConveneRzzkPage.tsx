import { useMemo, useState } from 'react';

import { formatNumber, levelBadgeClass, rzzkCase, voivodeshipRows } from '@/data/model';
import { useScenario } from '@/hooks/ScenarioContext';
import { DecisionForm } from '@/components/DecisionForm';
import { saveNotification, type DecisionRecord } from '@/services/decisions';
import { Badge, Button, EmptyState, Field, Panel, Toast, inputClass } from '@/components/ui';

/**
 * Ekran 5: zwolanie RZZK.
 *
 * Sedno demonstracji: system zestawia argumenty za i przeciw, wskazuje sklad
 * i przygotowuje projekt zawiadomienia, ale nie zwoluje zespolu automatycznie.
 * Decyzja i jej uzasadnienie sa zapisywane razem z migawka przeslanek.
 */
export function ConveneRzzkPage() {
  const { index, day, decisions, refresh, actor } = useScenario();
  const [formOpen, setFormOpen] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const [lastDecision, setLastDecision] = useState<DecisionRecord | null>(null);
  const [subject, setSubject] = useState('');
  const [body, setBody] = useState('');
  const [busy, setBusy] = useState(false);

  const kase = useMemo(() => (index ? rzzkCase(index, day) : null), [index, day]);
  const rows = useMemo(() => (index ? voivodeshipRows(index, day) : []), [index, day]);

  if (!index || !kase) return <EmptyState text="Wczytywanie sceny…" />;

  const country = index.countryByDay.get(day);
  const hazard = index.hazardByCode.get('Z02');
  const participants = [
    { name: 'Dyrektor RCB', role: 'sekretarz zespołu', why: 'prowadzi obraz sytuacji i protokół' },
    {
      name: hazard?.lead ?? 'minister wiodący',
      role: 'minister wiodący',
      why: `zagrożenie ${hazard?.code ?? 'Z02'} — ${hazard?.name ?? 'powódź'}`,
    },
    { name: 'MSWiA', role: 'współdziałanie', why: 'PSP, Policja, ochrona ludności' },
    { name: 'MON', role: 'współdziałanie', why: 'siły WOT zaangażowane w rejonie' },
    ...(country && country.off > 5000
      ? [{ name: 'Ministerstwo Klimatu i Środowiska', role: 'współdziałanie', why: 'przerwy w zasilaniu' }]
      : []),
    ...(country && country.minCov !== null && country.minCov < 50
      ? [{ name: 'Ministerstwo Cyfryzacji', role: 'współdziałanie', why: 'degradacja łączności' }]
      : []),
    ...rows
      .filter((r) => r.maxKis >= 45)
      .map((r) => ({
        name: `Wojewoda ${r.name}`,
        role: 'poziom wojewódzki',
        why: `maks. lokalny KIS ${r.maxKis}, ${r.alarmGminas} gmin w alarmie`,
      })),
  ];

  const draftNotification = () => {
    setSubject(`Zwołanie posiedzenia RZZK — doba ${day}`);
    setBody(
      [
        `Na podstawie obrazu sytuacji z doby ${day} zwołuję posiedzenie Rządowego Zespołu Zarządzania Kryzysowego.`,
        '',
        'Przesłanki:',
        ...kase.pros.map((a) => `— ${a}`),
        '',
        `Skład wezwany: ${participants.map((p) => p.name).join(', ')}.`,
        '',
        'Porządek: 1) obraz sytuacji, 2) uruchomienie SPO, 3) siły i środki, 4) komunikacja z ludnością.',
      ].join('\n')
    );
  };

  const sendNotification = async () => {
    setBusy(true);
    try {
      await saveNotification(
        {
          decision_id: lastDecision?.decision_id ?? 'BEZ-DECYZJI',
          channel: 'RZZK',
          recipients: participants.map((p) => p.name).join('; ').slice(0, 600),
          recipient_count: participants.length,
          subject: subject.trim() || `Zwołanie RZZK — ${day}`,
          body: body.trim().slice(0, 1500) || 'Zwołanie posiedzenia RZZK.',
          scene_day: day,
        },
        actor
      );
      setToast(`Zarejestrowano zawiadomienie dla ${participants.length} adresatów.`);
      void refresh();
    } catch (e: unknown) {
      setToast(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };

  const rzzkDecisions = decisions.filter((d) => d.chosen_level === 'RZZK');

  return (
    <div className="space-y-4">
      <Panel
        title="Czy zwołać RZZK?"
        subtitle={`doba ${day} · rekomendacja algorytmiczna: ${kase.recommendedLevel}`}
        tone={kase.suggestSummon ? 'alert' : 'accent'}
      >
        <div className="grid gap-4 lg:grid-cols-2">
          <div>
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-emerald-700">
              Argumenty za zwołaniem
            </p>
            {kase.pros.length === 0 ? (
              <EmptyState text="Brak przesłanek w tej dobie." />
            ) : (
              <ul className="space-y-1.5">
                {kase.pros.map((a) => (
                  <li
                    key={a}
                    className="rounded-lg bg-emerald-50 px-3 py-2 text-sm text-emerald-800 ring-1 ring-emerald-600/25"
                  >
                    {a}
                  </li>
                ))}
              </ul>
            )}
          </div>
          <div>
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-amber-700">
              Argumenty przeciw / zastrzeżenia
            </p>
            {kase.cons.length === 0 ? (
              <EmptyState text="Brak zastrzeżeń." />
            ) : (
              <ul className="space-y-1.5">
                {kase.cons.map((a) => (
                  <li
                    key={a}
                    className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-800 ring-1 ring-amber-600/25"
                  >
                    {a}
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>

        <div className="mt-4 flex flex-wrap items-center gap-3 rounded-lg bg-slate-50 px-4 py-3">
          <Badge className={levelBadgeClass(kase.suggestSummon ? 'RZZK' : kase.recommendedLevel)}>
            {kase.suggestSummon
              ? 'przesłanki uzasadniają zwołanie'
              : 'przesłanki nie są rozstrzygające'}
          </Badge>
          <span className="text-xs text-slate-500">
            maks. lokalny KIS {kase.maxKis} · kaskada {kase.cascade}/4 · województwa powyżej progu:{' '}
            {kase.affectedVoivodeships.length || '—'}
          </span>
          <Button variant="primary" className="ml-auto" onClick={() => setFormOpen(true)}>
            Zapisz decyzję o zwołaniu
          </Button>
        </div>
        <p className="mt-2 text-[11px] text-slate-500">
          System nie zwołuje zespołu samodzielnie. Rekomendacja i przesłanki są przygotowane po to,
          żeby decyzja człowieka była szybka i udokumentowana.
        </p>
      </Panel>

      <div className="grid gap-4 lg:grid-cols-2">
        <Panel title="Proponowany skład" subtitle={`${participants.length} adresatów`}>
          <ul className="space-y-1.5">
            {participants.map((p) => (
              <li key={p.name} className="rounded-lg bg-slate-50 px-3 py-2 text-sm">
                <div className="flex items-baseline justify-between gap-2">
                  <span className="font-medium text-slate-900">{p.name}</span>
                  <span className="text-[11px] uppercase tracking-wide text-slate-500">
                    {p.role}
                  </span>
                </div>
                <div className="text-xs text-slate-500">{p.why}</div>
              </li>
            ))}
          </ul>
          {hazard && (
            <p className="mt-3 rounded-lg bg-slate-50 px-3 py-2 text-xs text-slate-500">
              Współdziałający wg siatki bezpieczeństwa dla {hazard.code}: {hazard.coop}
            </p>
          )}
        </Panel>

        <Panel
          title="Zawiadomienie"
          subtitle="projekt treści do rozesłania"
          right={<Button onClick={draftNotification}>Wygeneruj projekt</Button>}
        >
          <div className="space-y-3">
            <Field label="Temat">
              <input
                value={subject}
                onChange={(e) => setSubject(e.target.value)}
                className={inputClass}
              />
            </Field>
            <Field label="Treść">
              <textarea
                value={body}
                onChange={(e) => setBody(e.target.value)}
                rows={12}
                className={`${inputClass} font-mono text-xs`}
              />
            </Field>
            <div className="flex items-center justify-between">
              <span className="text-xs text-slate-500">
                {lastDecision
                  ? `Powiązane z decyzją ${lastDecision.decision_id}`
                  : 'Zapisz najpierw decyzję, aby powiązać zawiadomienie.'}
              </span>
              <Button
                variant="primary"
                onClick={() => void sendNotification()}
                disabled={busy || body.trim().length < 3}
              >
                {busy ? 'Zapisywanie…' : 'Zarejestruj wysyłkę'}
              </Button>
            </div>
          </div>
        </Panel>
      </div>

      {country && (
        <Panel title="Obraz w liczbach" subtitle="dane, na których opiera się rekomendacja">
          <div className="grid grid-cols-2 gap-3 text-sm md:grid-cols-4 xl:grid-cols-7">
            {[
              ['KIS krajowy', country.kis],
              ['Maks. lokalny KIS', country.maxKis],
              ['Gminy w alarmie', country.alarmGminas],
              ['Ewakuowani', country.evac],
              ['Bez zasilania', country.off],
              ['Zgłoszenia', country.inc],
              ['Dezinformacja', country.disinfo],
            ].map(([label, value]) => (
              <div key={String(label)} className="rounded-lg bg-slate-50 px-3 py-2">
                <div className="text-[11px] uppercase tracking-wide text-slate-500">{label}</div>
                <div className="text-lg font-semibold tabular-nums text-slate-900">
                  {formatNumber(Number(value))}
                </div>
              </div>
            ))}
          </div>
        </Panel>
      )}

      {rzzkDecisions.length > 0 && (
        <Panel title="Zapisane decyzje o poziomie RZZK">
          <ul className="space-y-1.5 text-sm">
            {rzzkDecisions.map((d) => (
              <li key={d.id} className="rounded-lg bg-slate-50 px-3 py-2">
                <span className="font-mono text-xs text-slate-500">
                  {d.decision_id} v{d.version}
                </span>{' '}
                <span className="text-slate-900">{d.title}</span>
                <span className="block text-[11px] text-slate-500">
                  {d.author_name} · {d.author_role} · {d.status}
                </span>
              </li>
            ))}
          </ul>
        </Panel>
      )}

      <DecisionForm
        open={formOpen}
        onClose={() => setFormOpen(false)}
        onSaved={(rec) => {
          setLastDecision(rec);
          setToast(`Zapisano decyzję ${rec.decision_id}.`);
          void refresh();
          if (!subject) draftNotification();
        }}
        day={day}
        scope="kraj"
        voivodeshipCode=""
        recommendedLevel={kase.recommendedLevel}
        recommendedSpo={['SPO-1', 'SPO-2', 'SPO-3', 'SPO-10']}
        kis={kase.maxKis}
        defaultTitle={`Zwołanie RZZK — doba ${day}`}
        defaultText={
          kase.pros.length
            ? `Zwołuję posiedzenie RZZK. Przesłanki: ${kase.pros.join(' ')}`
            : ''
        }
      />

      <Toast message={toast} onDone={() => setToast(null)} />
    </div>
  );
}
