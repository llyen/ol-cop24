import { useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';

import {
  cascadeSignals,
  formatNumber,
  gminaRows,
  kisBreakdown,
  kisColor,
  levelBadgeClass,
  toCsv,
  voivSeries,
  voivodeshipRows,
} from '@/data/model';
import { useScenario } from '@/hooks/ScenarioContext';
import { saveBrief } from '@/services/decisions';
import {
  Badge,
  BarList,
  Button,
  CountryMap,
  EmptyState,
  Field,
  KpiCard,
  Modal,
  Panel,
  Sparkline,
  Toast,
  downloadCsv,
  inputClass,
  type MapPoint,
} from '@/components/ui';

export function VoivodeshipPage() {
  const { index, day, dayIndex, actor, refresh } = useScenario();
  const [params, setParams] = useSearchParams();
  const navigate = useNavigate();
  const [selectedGmina, setSelectedGmina] = useState<string | null>(null);
  const [briefOpen, setBriefOpen] = useState(false);
  const [toast, setToast] = useState<string | null>(null);

  const rows = useMemo(() => (index ? voivodeshipRows(index, day) : []), [index, day]);
  const code = params.get('v') || rows[0]?.v || '';
  const row = rows.find((r) => r.v === code);
  const gminas = useMemo(
    () => (index && code ? gminaRows(index, day, code) : []),
    [index, day, code]
  );

  if (!index) return <EmptyState text="Wczytywanie sceny…" />;
  if (!row) return <EmptyState text="Wybierz województwo." />;

  const gmina = gminas.find((g) => g.g === selectedGmina) ?? gminas[0];
  const cascade = cascadeSignals(row);
  const points: MapPoint[] = gminas.map((g) => ({
    id: g.g,
    lat: g.lat,
    lon: g.lon,
    value: g.kis,
    label: g.name,
    detail: `KIS ${g.kis} · zgłoszenia ${g.inc}`,
    alarm: g.alarm === 1,
  }));

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <select
          value={code}
          onChange={(e) => {
            setParams({ v: e.target.value });
            setSelectedGmina(null);
          }}
          className="rounded-lg bg-slate-800 px-3 py-2 text-sm text-slate-100 ring-1 ring-slate-600"
        >
          {rows.map((r) => (
            <option key={r.v} value={r.v}>
              {r.name} — maks. KIS {r.maxKis}
            </option>
          ))}
        </select>
        <Badge className={levelBadgeClass(row.rec.level)}>
          rekomendowany poziom: {row.rec.level}
        </Badge>
        <span className="text-xs text-slate-500">
          WCZK {row.seat} · ludność {formatNumber(row.pop)}
        </span>
        <div className="ml-auto flex gap-2">
          <Button onClick={() => setBriefOpen(true)}>Zamów brief</Button>
          <Button variant="primary" onClick={() => navigate(`/rekomendacje?v=${row.v}`)}>
            Przejdź do rekomendacji SPO
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        <KpiCard
          label="KIS województwa"
          value={row.kis}
          prev={row.delta === null ? null : row.kis - row.delta}
          spark={voivSeries(index, row.v, 'kis')}
          hint="Średnia z gmin województwa."
          emphasis
        />
        <KpiCard label="Maks. lokalny KIS" value={row.maxKis} hint="Najgorsza gmina." />
        <KpiCard label="Gminy w alarmie" value={row.alarmGminas} hint="Przekroczony stan alarmowy." />
        <KpiCard label="Zgłoszenia" value={row.inc} hint={`w tym priorytet 1: ${row.p1}`} />
        <KpiCard label="Bez zasilania" value={row.off} hint="Odbiorcy w dobie." />
        <KpiCard label="Ewakuowani" value={row.evac} hint="Osoby objęte ewakuacją." />
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <Panel title="Gminy" subtitle={`${gminas.length} gmin z sygnałem`} className="xl:col-span-2">
          <div className="max-h-[420px] overflow-y-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-slate-900">
                <tr className="border-b border-slate-700 text-left text-[11px] uppercase tracking-wider text-slate-500">
                  <th className="py-2 pr-2">Gmina</th>
                  <th className="px-2">Powiat</th>
                  <th className="px-2 text-right">KIS</th>
                  <th className="px-2 text-right">Stan wody</th>
                  <th className="px-2 text-right">Zgłoszenia</th>
                  <th className="px-2 text-right">Bez prądu</th>
                  <th className="px-2 text-right">Ewakuacja</th>
                  <th className="px-2 text-right">Pokrycie</th>
                </tr>
              </thead>
              <tbody>
                {gminas.map((g) => (
                  <tr
                    key={g.g}
                    onClick={() => setSelectedGmina(g.g)}
                    className={`cursor-pointer border-b border-slate-800/70 transition-colors hover:bg-slate-800/60 ${
                      gmina?.g === g.g ? 'bg-slate-800/80' : ''
                    }`}
                  >
                    <td className="py-1.5 pr-2">
                      <span className="flex items-center gap-2">
                        <span
                          className="inline-block h-2 w-2 rounded-full"
                          style={{ background: kisColor(g.kis) }}
                        />
                        <span className="text-slate-200">{g.name}</span>
                        {g.alarm === 1 && (
                          <Badge className="bg-red-500/15 text-red-300 ring-red-500/40">alarm</Badge>
                        )}
                      </span>
                    </td>
                    <td className="px-2 text-slate-400">{g.powiat}</td>
                    <td className="px-2 text-right font-medium tabular-nums text-slate-100">
                      {g.kis}
                    </td>
                    <td className="px-2 text-right tabular-nums text-slate-300">
                      {g.lvl ? `${g.lvl} cm` : '—'}
                    </td>
                    <td className="px-2 text-right tabular-nums text-slate-300">{g.inc}</td>
                    <td className="px-2 text-right tabular-nums text-slate-300">
                      {formatNumber(g.off)}
                    </td>
                    <td className="px-2 text-right tabular-nums text-slate-300">
                      {formatNumber(g.evac)}
                    </td>
                    <td className="px-2 text-right tabular-nums text-slate-300">
                      {g.cov === null ? '—' : `${g.cov}%`}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="mt-3 flex justify-end">
            <Button
              onClick={() =>
                downloadCsv(
                  `gminy_${row.name}_${day}.csv`,
                  toCsv(
                    gminas.map((g) => ({
                      data: day,
                      gmina: g.name,
                      powiat: g.powiat,
                      kis: g.kis,
                      stan_wody_cm: g.lvl,
                      zgloszenia: g.inc,
                      bez_pradu: g.off,
                      ewakuowani: g.evac,
                      pokrycie_pct: g.cov ?? '',
                      rekomendacja: g.rec.level,
                    }))
                  )
                )
              }
            >
              Eksport CSV
            </Button>
          </div>
        </Panel>

        <div className="space-y-4">
          {gmina && (
            <Panel
              title={`Dlaczego ${gmina.name} ma KIS ${gmina.kis}`}
              subtitle="rozbicie indeksu na składowe"
              tone="accent"
            >
              <BarList
                rows={kisBreakdown(index, gmina).map((b) => ({
                  label: b.label,
                  value: b.value,
                }))}
                color="#22d3ee"
              />
              <p className="mt-3 text-[11px] leading-relaxed text-slate-500">
                {index.scene.meta.kisFormula}. Suma składowych daje wartość indeksu, obciętą do 100.
              </p>
            </Panel>
          )}

          <Panel title="Kaskada w województwie">
            <div className="space-y-2">
              {cascade.map((c) => (
                <div
                  key={c.key}
                  className={`flex items-center justify-between rounded-lg px-3 py-2 text-sm ring-1 ${
                    c.active
                      ? 'bg-orange-500/10 text-orange-200 ring-orange-500/30'
                      : 'bg-slate-800/50 text-slate-400 ring-slate-700'
                  }`}
                >
                  <span>{c.label}</span>
                  <span className="text-xs tabular-nums">{c.detail}</span>
                </div>
              ))}
            </div>
          </Panel>

          <Panel title="Siły i środki" subtitle="stan zaangażowania w dobie">
            <BarList
              rows={[
                { label: 'Zastępy PSP', value: row.res.psp_units ?? 0 },
                { label: 'Żołnierze WOT', value: row.res.wot_soldiers ?? 0 },
                { label: 'Pompy', value: row.res.pumps ?? 0 },
                { label: 'Agregaty', value: row.res.generators ?? 0 },
                { label: 'Śmigłowce', value: row.res.helicopters ?? 0 },
              ]}
              color="#34d399"
            />
          </Panel>

          <Panel title="Przebieg KIS województwa">
            <Sparkline values={voivSeries(index, row.v, 'kis')} height={60} marker={dayIndex} />
            <p className="mt-2 text-[11px] text-slate-500">
              Punkt oznacza wybraną dobę. Cała scena obejmuje {index.days.length} dób.
            </p>
          </Panel>
        </div>
      </div>

      <Panel title="Rozkład w województwie">
        <CountryMap
          points={points}
          anchors={[
            {
              id: row.v,
              lat: index.voivByCode.get(row.v)?.lat ?? 0,
              lon: index.voivByCode.get(row.v)?.lon ?? 0,
              value: row.maxKis,
              label: row.seat,
            },
          ]}
          selectedId={gmina?.g ?? null}
          onSelect={setSelectedGmina}
          height={320}
        />
      </Panel>

      <BriefModal
        open={briefOpen}
        onClose={() => setBriefOpen(false)}
        onSaved={(msg) => {
          setToast(msg);
          void refresh();
        }}
        day={day}
        voivCode={row.v}
        voivName={row.name}
        actorName={actor.name}
      />
      <Toast message={toast} onDone={() => setToast(null)} />
    </div>
  );
}

function BriefModal({
  open,
  onClose,
  onSaved,
  day,
  voivCode,
  voivName,
  actorName,
}: {
  open: boolean;
  onClose: () => void;
  onSaved: (msg: string) => void;
  day: string;
  voivCode: string;
  voivName: string;
  actorName: string;
}) {
  const { actor } = useScenario();
  const [audience, setAudience] = useState('RZZK');
  const [format, setFormat] = useState('nota 1 strona');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async () => {
    setBusy(true);
    setError(null);
    try {
      await saveBrief(
        {
          scene_day: day,
          scope: 'województwo',
          voivodeship_code: voivCode,
          audience,
          format,
          note: note.trim(),
          status: 'zamówiony',
        },
        actor
      );
      onSaved(`Zamówiono ${format} dla: ${audience}.`);
      onClose();
      setNote('');
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal open={open} title={`Zamów brief — ${voivName}`} onClose={onClose}>
      <div className="space-y-4">
        <Field label="Odbiorca">
          <select
            value={audience}
            onChange={(e) => setAudience(e.target.value)}
            className={inputClass}
          >
            <option>RZZK</option>
            <option>Prezes Rady Ministrów</option>
            <option>minister wiodący</option>
            <option>wojewoda</option>
          </select>
        </Field>
        <Field label="Format">
          <select value={format} onChange={(e) => setFormat(e.target.value)} className={inputClass}>
            <option>nota 1 strona</option>
            <option>prezentacja</option>
            <option>komunikat prasowy</option>
          </select>
        </Field>
        <Field label="Uwagi" hint="Np. akcent na ewakuację i stan łączności.">
          <textarea
            value={note}
            onChange={(e) => setNote(e.target.value)}
            rows={4}
            className={inputClass}
          />
        </Field>
        <p className="text-xs text-slate-500">
          Zamawiający: {actorName} · doba {day}
        </p>
        {error && <p className="text-sm text-red-400">{error}</p>}
        <div className="flex justify-end gap-2">
          <Button onClick={onClose}>Anuluj</Button>
          <Button variant="primary" onClick={() => void submit()} disabled={busy}>
            {busy ? 'Zapisywanie…' : 'Zamów'}
          </Button>
        </div>
      </div>
    </Modal>
  );
}
