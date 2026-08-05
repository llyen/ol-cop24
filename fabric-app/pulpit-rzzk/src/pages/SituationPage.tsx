import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';

import {
  cascadeSignals,
  countryKpis,
  countrySeries,
  formatNumber,
  gminaRows,
  kisColor,
  KIS_LEGEND,
  levelBadgeClass,
  toCsv,
  voivodeshipRows,
  wavePropagation,
} from '@/data/model';
import { useScenario } from '@/hooks/ScenarioContext';
import {
  Badge,
  BarList,
  Button,
  CountryMap,
  EmptyState,
  KpiCard,
  Panel,
  TimelineBars,
  downloadCsv,
  type MapPoint,
} from '@/components/ui';

export function SituationPage() {
  const { index, day, dayIndex, setDayIndex } = useScenario();
  const navigate = useNavigate();
  const [selected, setSelected] = useState<string | null>(null);

  const data = useMemo(() => {
    if (!index) return null;
    const country = index.countryByDay.get(day);
    const voivs = voivodeshipRows(index, day);
    const gminas = gminaRows(index, day);
    const points: MapPoint[] = gminas
      .filter((g) => g.kis >= 5)
      .map((g) => ({
        id: g.g,
        lat: g.lat,
        lon: g.lon,
        value: g.kis,
        label: `${g.name} (${g.vName})`,
        detail: `KIS ${g.kis} · zgłoszenia ${g.inc} · bez prądu ${formatNumber(g.off)}${
          g.alarm === 1 ? ' · STAN ALARMOWY' : ''
        }`,
        alarm: g.alarm === 1,
      }));
    const anchors: MapPoint[] = voivs.map((v) => ({
      id: v.v,
      lat: index.voivByCode.get(v.v)?.lat ?? 0,
      lon: index.voivByCode.get(v.v)?.lon ?? 0,
      value: v.maxKis,
      label: v.seat,
    }));
    return {
      country,
      voivs,
      gminas,
      points,
      anchors,
      wave: wavePropagation(index, day),
      media: (index.mediaByDay.get(day) ?? [])
        .slice()
        .sort((a, b) => b.count - a.count)
        .slice(0, 6),
    };
  }, [index, day]);

  if (!index || !data || !data.country) return <EmptyState text="Wczytywanie sceny…" />;
  const { country, voivs, gminas, points, anchors, wave, media } = data;
  const kpis = countryKpis(index, day);
  const cascade = cascadeSignals(country);
  const activeCascade = cascade.filter((c) => c.active).length;

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4 xl:grid-cols-8">
        {kpis.map((k) => (
          <KpiCard
            key={k.key}
            label={k.label}
            value={k.value}
            prev={k.prev}
            unit={k.unit}
            hint={k.hint}
            higherIsWorse={k.higherIsWorse}
            emphasis={k.key === 'maxKis'}
            spark={
              k.key === 'kis'
                ? countrySeries(index, 'kis')
                : k.key === 'maxKis'
                  ? countrySeries(index, 'maxKis')
                  : undefined
            }
          />
        ))}
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <Panel
          title="Rozkład przestrzenny zagrożenia"
          subtitle={`${points.length} gmin z sygnałem · pierścień = siedziba WCZK`}
          className="xl:col-span-2"
          tone="accent"
        >
          <CountryMap
            points={points}
            anchors={anchors}
            colorFor={kisColor}
            legend={KIS_LEGEND}
            selectedId={selected}
            onSelect={(id) => setSelected(id === selected ? null : id)}
          />
          {selected && (
            <SelectedGmina
              code={selected}
              onOpen={(v) => navigate(`/wojewodztwo?v=${v}`)}
              rows={gminas}
            />
          )}
        </Panel>

        <div className="space-y-4">
          <Panel
            title="Kaskada wieloresortowa"
            subtitle={`${activeCascade} z 4 obszarów aktywnych`}
            tone={activeCascade >= 3 ? 'alert' : 'default'}
          >
            <div className="space-y-2">
              {cascade.map((c) => (
                <div
                  key={c.key}
                  className={`flex items-center justify-between rounded-lg px-3 py-2 text-sm ring-1 ${
                    c.active
                      ? 'bg-red-50 text-red-800 ring-red-600/30'
                      : 'bg-slate-50 text-slate-500 ring-slate-200'
                  }`}
                >
                  <span className="font-medium">{c.label}</span>
                  <span className="text-xs tabular-nums">{c.detail}</span>
                </div>
              ))}
            </div>
            {activeCascade >= 3 && (
              <p className="mt-3 rounded-lg bg-red-50 px-3 py-2 text-xs text-red-800 ring-1 ring-red-600/30">
                Zagrożenie przestało być jednoresortowe. To przesłanka do rozważenia zwołania RZZK —
                przejdź do zakładki „Zwołaj RZZK”.
              </p>
            )}
          </Panel>

          <Panel title="Propagacja fali" subtitle="wodowskazy powyżej stanu ostrzegawczego">
            {wave.length === 0 ? (
              <EmptyState text="Żaden wodowskaz nie przekracza progów w tej dobie." />
            ) : (
              <ol className="space-y-1.5">
                {wave.map((w) => {
                  const pct = Math.min((w.level / w.alarm) * 100, 140);
                  return (
                    <li key={w.gaugeId} className="rounded-lg bg-slate-50 px-3 py-2">
                      <div className="flex items-baseline justify-between gap-2 text-xs">
                        <span className="truncate font-medium text-slate-900">
                          {w.gaugeName} · {w.river}
                        </span>
                        <span className="tabular-nums text-slate-500">
                          {w.level} cm / alarm {w.alarm}
                        </span>
                      </div>
                      <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-white">
                        <div
                          className="h-full rounded-full transition-all duration-500"
                          style={{
                            width: `${Math.min(pct, 100)}%`,
                            background: w.state === 'alarm' ? '#d5233f' : '#b45309',
                          }}
                        />
                      </div>
                      <div className="mt-1 flex justify-between text-[11px] text-slate-500">
                        <span>
                          {w.gminaName} · trend {w.trend === 'rising' ? 'rosnący' : w.trend === 'falling' ? 'opadający' : 'stabilny'}
                        </span>
                        <span>+{w.etaHours} h od profilu górnego</span>
                      </div>
                    </li>
                  );
                })}
              </ol>
            )}
          </Panel>
        </div>
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <Panel
          title="Województwa"
          subtitle="sortowanie po maks. lokalnym KIS"
          className="xl:col-span-2"
          right={
            <Button
              onClick={() =>
                downloadCsv(
                  `wojewodztwa_${day}.csv`,
                  toCsv(
                    voivs.map((v) => ({
                      data: day,
                      wojewodztwo: v.name,
                      kis: v.kis,
                      maks_kis: v.maxKis,
                      gminy_alarm: v.alarmGminas,
                      zgloszenia: v.inc,
                      bez_pradu: v.off,
                      ewakuowani: v.evac,
                      rekomendacja: v.rec.level,
                    }))
                  )
                )
              }
            >
              Eksport CSV
            </Button>
          }
        >
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-[11px] uppercase tracking-wider text-slate-500">
                  <th className="py-2 pr-2">Województwo</th>
                  <th className="px-2 text-right">KIS</th>
                  <th className="px-2 text-right">Maks.</th>
                  <th className="px-2 text-right">Alarm</th>
                  <th className="px-2 text-right">Zgłoszenia</th>
                  <th className="px-2 text-right">Bez prądu</th>
                  <th className="px-2 text-right">Ewakuacja</th>
                  <th className="px-2">Rekomendacja</th>
                </tr>
              </thead>
              <tbody>
                {voivs.map((v) => (
                  <tr
                    key={v.v}
                    onClick={() => navigate(`/wojewodztwo?v=${v.v}`)}
                    className="cursor-pointer border-b border-slate-200 transition-colors hover:bg-slate-50"
                  >
                    <td className="py-1.5 pr-2">
                      <span className="flex items-center gap-2">
                        <span
                          className="inline-block h-2 w-2 rounded-full"
                          style={{ background: kisColor(v.maxKis) }}
                        />
                        <span className="text-slate-900">{v.name}</span>
                      </span>
                    </td>
                    <td className="px-2 text-right tabular-nums text-slate-700">
                      {v.kis}
                      {v.delta !== null && v.delta !== 0 && (
                        <span
                          className={`ml-1 text-[10px] ${v.delta > 0 ? 'text-red-700' : 'text-emerald-700'}`}
                        >
                          {v.delta > 0 ? '▲' : '▼'}
                        </span>
                      )}
                    </td>
                    <td className="px-2 text-right font-medium tabular-nums text-slate-900">
                      {v.maxKis}
                    </td>
                    <td className="px-2 text-right tabular-nums text-slate-700">{v.alarmGminas}</td>
                    <td className="px-2 text-right tabular-nums text-slate-700">{v.inc}</td>
                    <td className="px-2 text-right tabular-nums text-slate-700">
                      {formatNumber(v.off)}
                    </td>
                    <td className="px-2 text-right tabular-nums text-slate-700">
                      {formatNumber(v.evac)}
                    </td>
                    <td className="px-2">
                      <Badge className={levelBadgeClass(v.rec.level)}>{v.rec.level}</Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Panel>

        <div className="space-y-4">
          <Panel title="Przebieg doby po dobie" subtitle="kliknij słupek, aby przejść do dnia">
            <p className="mb-1 text-[11px] uppercase tracking-wide text-slate-500">
              Maks. lokalny KIS
            </p>
            <TimelineBars
              values={countrySeries(index, 'maxKis')}
              labels={index.days}
              activeIndex={dayIndex}
              onSelect={setDayIndex}
              colorFor={kisColor}
            />
            <p className="mt-3 mb-1 text-[11px] uppercase tracking-wide text-slate-500">
              Zgłoszenia 112 / PSP
            </p>
            <TimelineBars
              values={countrySeries(index, 'inc')}
              labels={index.days}
              activeIndex={dayIndex}
              onSelect={setDayIndex}
              height={44}
            />
            <p className="mt-3 mb-1 text-[11px] uppercase tracking-wide text-slate-500">
              Sygnały dezinformacji
            </p>
            <TimelineBars
              values={countrySeries(index, 'disinfo')}
              labels={index.days}
              activeIndex={dayIndex}
              onSelect={setDayIndex}
              height={44}
              colorFor={() => '#7e22ce'}
            />
          </Panel>

          <Panel title="Obraz informacyjny" subtitle={`${country.media} sygnałów w dobie`}>
            <BarList
              rows={media.map((m) => ({
                label: `${m.topic}${m.disinfo ? ` · ${m.disinfo} dezinf.` : ''}`,
                value: m.count,
                hint: `zasięg ${formatNumber(m.reach)}`,
              }))}
              color="#7e22ce"
            />
            <div className="mt-3 rounded-lg bg-slate-50 px-3 py-2 text-xs text-slate-500">
              Zasięg treści oznaczonych jako dezinformacja:{' '}
              <span className="font-semibold text-slate-900">
                {formatNumber(country.disinfoReach)}
              </span>
            </div>
          </Panel>

          <Panel title="Dominujące typy zdarzeń">
            <BarList
              rows={country.topTypes.map(([label, value]) => ({ label, value }))}
              color="#0052a5"
            />
          </Panel>
        </div>
      </div>
    </div>
  );
}

function SelectedGmina({
  code,
  rows,
  onOpen,
}: {
  code: string;
  rows: ReturnType<typeof gminaRows>;
  onOpen: (voiv: string) => void;
}) {
  const row = rows.find((r) => r.g === code);
  if (!row) return null;
  return (
    <div className="mt-3 flex flex-wrap items-center gap-3 rounded-lg bg-slate-50 px-4 py-3 text-sm ring-1 ring-slate-200">
      <span className="font-semibold text-slate-900">{row.name}</span>
      <span className="text-slate-500">
        {row.powiat} · {row.vName}
      </span>
      <Badge className={levelBadgeClass(row.rec.level)}>KIS {row.kis} → {row.rec.level}</Badge>
      <span className="text-xs text-slate-500">
        zgłoszenia {row.inc} · bez prądu {formatNumber(row.off)} · ewakuacja{' '}
        {formatNumber(row.evac)}
        {row.cov !== null ? ` · pokrycie ${row.cov}%` : ''}
      </span>
      <Button className="ml-auto" onClick={() => onOpen(row.v)}>
        Otwórz kartę województwa
      </Button>
    </div>
  );
}
