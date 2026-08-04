import { useMemo, useState } from 'react';

import { formatNumber, levelBadgeClass, toCsv } from '@/data/model';
import { useScenario } from '@/hooks/ScenarioContext';
import { DecisionEvidencePanel } from '@/components/DecisionForm';
import { DecisionForm } from '@/components/DecisionForm';
import {
  latestVersions,
  saveAction,
  updateActionStatus,
  versionsOf,
  type DecisionRecord,
} from '@/services/decisions';
import {
  Badge,
  Button,
  EmptyState,
  Field,
  Modal,
  Panel,
  Toast,
  downloadCsv,
  inputClass,
} from '@/components/ui';

const STATUS_CLASS: Record<string, string> = {
  projekt: 'bg-slate-500/15 text-slate-300 ring-slate-500/40',
  zatwierdzona: 'bg-emerald-500/15 text-emerald-300 ring-emerald-500/40',
  odrzucona: 'bg-red-500/15 text-red-300 ring-red-500/40',
  wycofana: 'bg-amber-500/15 text-amber-300 ring-amber-500/40',
};

const ACTION_STATUSES = ['nie rozpoczęto', 'w toku', 'gotowe', 'zablokowane'];

/**
 * Ekran 4: rejestr decyzji.
 *
 * Decyzji nie da sie usunac ani nadpisac. Kazda korekta to nowa wersja
 * z zachowanym decision_id, wlasnym skrotem przeslanek i autorem.
 */
export function DecisionsPage() {
  const { index, decisions, actions, briefs, notifications, refresh, actor } = useScenario();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [newVersionFor, setNewVersionFor] = useState<DecisionRecord | null>(null);
  const [actionFor, setActionFor] = useState<DecisionRecord | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [showAll, setShowAll] = useState(false);

  const latest = useMemo(() => latestVersions(decisions), [decisions]);
  const shown = showAll ? decisions : latest;
  const selected = decisions.find((d) => d.decision_id === selectedId) ?? null;
  const history = selectedId ? versionsOf(decisions, selectedId) : [];

  if (!index) return <EmptyState text="Wczytywanie sceny…" />;

  return (
    <div className="space-y-4">
      <div className="grid gap-4 xl:grid-cols-3">
        <Panel
          title="Rejestr decyzji"
          subtitle={`${latest.length} decyzji · ${decisions.length} wersji łącznie`}
          className="xl:col-span-2"
          right={
            <div className="flex gap-2">
              <Button onClick={() => setShowAll((s) => !s)}>
                {showAll ? 'Tylko aktualne' : 'Wszystkie wersje'}
              </Button>
              <Button
                disabled={decisions.length === 0}
                onClick={() =>
                  downloadCsv(
                    'rejestr_decyzji.csv',
                    toCsv(
                      decisions.map((d) => ({
                        decyzja: d.decision_id,
                        wersja: d.version,
                        zastepuje_wersje: d.supersedes_version,
                        doba: d.scene_day,
                        zakres: d.scope,
                        wojewodztwo: index.voivByCode.get(d.voivodeship_code)?.name ?? '',
                        tytul: d.title,
                        tresc: d.decision_text,
                        rekomendacja: d.recommended_level,
                        decyzja_poziom: d.chosen_level,
                        spo: d.spo_codes,
                        status: d.status,
                        kis: d.kis_at_decision,
                        skrot: d.audit_hash,
                        autor: d.author_name,
                        rola: d.author_role,
                        zapisano: new Date(d.created_at).toISOString(),
                      }))
                    )
                  )
                }
              >
                Eksport CSV
              </Button>
            </div>
          }
        >
          {shown.length === 0 ? (
            <EmptyState text="Brak decyzji. Zapisz pierwszą z zakładki „Rekomendowane SPO” albo „Zwołaj RZZK”." />
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-slate-700 text-left text-[11px] uppercase tracking-wider text-slate-500">
                    <th className="py-2 pr-2">Decyzja</th>
                    <th className="px-2">Tytuł</th>
                    <th className="px-2">Doba</th>
                    <th className="px-2">Poziom</th>
                    <th className="px-2">Status</th>
                    <th className="px-2">Autor</th>
                  </tr>
                </thead>
                <tbody>
                  {shown.map((d) => (
                    <tr
                      key={d.id}
                      onClick={() => setSelectedId(d.decision_id)}
                      className={`cursor-pointer border-b border-slate-800/70 hover:bg-slate-800/60 ${
                        selectedId === d.decision_id ? 'bg-slate-800/80' : ''
                      }`}
                    >
                      <td className="py-1.5 pr-2 font-mono text-xs text-slate-300">
                        {d.decision_id}
                        <span className="ml-1 text-slate-500">v{d.version}</span>
                      </td>
                      <td className="px-2 text-slate-200">{d.title}</td>
                      <td className="px-2 tabular-nums text-slate-400">{d.scene_day}</td>
                      <td className="px-2">
                        <Badge className={levelBadgeClass(d.chosen_level)}>{d.chosen_level}</Badge>
                        {d.chosen_level !== d.recommended_level && (
                          <span
                            className="ml-1 text-[10px] text-amber-400"
                            title={`Rekomendacja systemu: ${d.recommended_level}`}
                          >
                            ≠
                          </span>
                        )}
                      </td>
                      <td className="px-2">
                        <Badge className={STATUS_CLASS[d.status] ?? STATUS_CLASS.projekt}>
                          {d.status}
                        </Badge>
                      </td>
                      <td className="px-2 text-xs text-slate-400">
                        {d.author_name}
                        <span className="block text-slate-600">{d.author_role}</span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Panel>

        <div className="space-y-4">
          <Panel title="Zamówione briefy" subtitle={`${briefs.length}`}>
            {briefs.length === 0 ? (
              <EmptyState text="Brak zamówień." />
            ) : (
              <ul className="space-y-1.5 text-sm">
                {briefs.slice(0, 8).map((b) => (
                  <li key={b.id} className="rounded-lg bg-slate-800/50 px-3 py-2">
                    <div className="text-slate-200">
                      {b.format} → {b.audience}
                    </div>
                    <div className="text-[11px] text-slate-500">
                      doba {b.scene_day} ·{' '}
                      {index.voivByCode.get(b.voivodeship_code)?.name ?? 'kraj'} · {b.author_name}
                    </div>
                    {b.note && <div className="mt-1 text-xs text-slate-400">{b.note}</div>}
                  </li>
                ))}
              </ul>
            )}
          </Panel>

          <Panel title="Powiadomienia" subtitle={`${notifications.length}`}>
            {notifications.length === 0 ? (
              <EmptyState text="Brak wysłanych powiadomień." />
            ) : (
              <ul className="space-y-1.5 text-sm">
                {notifications.slice(0, 8).map((n) => (
                  <li key={n.id} className="rounded-lg bg-slate-800/50 px-3 py-2">
                    <div className="text-slate-200">{n.subject}</div>
                    <div className="text-[11px] text-slate-500">
                      kanał {n.channel} · adresatów {formatNumber(n.recipient_count)} · doba{' '}
                      {n.scene_day}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </Panel>
        </div>
      </div>

      {selected && (
        <Panel
          title={`${selected.decision_id} — ${selected.title}`}
          subtitle={`wersja ${history[history.length - 1]?.version ?? selected.version} · ${selected.scope}`}
          tone="accent"
          right={
            <div className="flex gap-2">
              <Button onClick={() => setActionFor(history[history.length - 1] ?? selected)}>
                Dodaj zadanie SPO
              </Button>
              <Button
                variant="primary"
                onClick={() => setNewVersionFor(history[history.length - 1] ?? selected)}
              >
                Nowa wersja
              </Button>
            </div>
          }
        >
          <div className="grid gap-4 lg:grid-cols-2">
            <div className="space-y-3">
              <p className="whitespace-pre-wrap rounded-lg bg-slate-800/50 px-4 py-3 text-sm text-slate-200">
                {history[history.length - 1]?.decision_text ?? selected.decision_text}
              </p>
              <div className="flex flex-wrap gap-1.5">
                {(history[history.length - 1]?.spo_codes ?? selected.spo_codes)
                  .split(',')
                  .filter(Boolean)
                  .map((code) => (
                    <Badge key={code} className="bg-cyan-500/15 text-cyan-300 ring-cyan-500/40">
                      {code} · {index.spoByCode.get(code)?.name?.slice(0, 40) ?? ''}
                    </Badge>
                  ))}
              </div>

              <div>
                <p className="mb-1.5 text-[11px] uppercase tracking-wide text-slate-500">
                  Historia wersji
                </p>
                <ol className="space-y-1.5">
                  {history.map((h) => (
                    <li
                      key={h.id}
                      className="flex items-center justify-between rounded-lg bg-slate-800/50 px-3 py-2 text-xs"
                    >
                      <span className="text-slate-300">
                        v{h.version}
                        {h.supersedes_version > 0 && (
                          <span className="text-slate-500"> (zastępuje v{h.supersedes_version})</span>
                        )}{' '}
                        · {h.chosen_level} · {h.status}
                      </span>
                      <span className="text-slate-500">
                        {h.author_name} · {new Date(h.created_at).toLocaleString('pl-PL')}
                      </span>
                    </li>
                  ))}
                </ol>
              </div>

              <div>
                <p className="mb-1.5 text-[11px] uppercase tracking-wide text-slate-500">
                  Zadania SPO
                </p>
                {actions.filter((a) => a.decision_id === selected.decision_id).length === 0 ? (
                  <EmptyState text="Brak zadań." />
                ) : (
                  <ul className="space-y-1.5">
                    {actions
                      .filter((a) => a.decision_id === selected.decision_id)
                      .map((a) => (
                        <li
                          key={a.id}
                          className="flex items-center justify-between gap-2 rounded-lg bg-slate-800/50 px-3 py-2 text-xs"
                        >
                          <span className="text-slate-200">
                            <span className="font-medium text-cyan-300">{a.spo_code}</span>{' '}
                            {a.action_text}
                            <span className="block text-slate-500">
                              {a.owner || 'bez właściciela'}
                              {a.due_day ? ` · termin ${a.due_day}` : ''}
                            </span>
                          </span>
                          <select
                            value={a.status}
                            onChange={(e) => {
                              void updateActionStatus(a.id, e.target.value).then(() => {
                                setToast('Zaktualizowano status zadania.');
                                void refresh();
                              });
                            }}
                            className="rounded bg-slate-900 px-2 py-1 text-[11px] text-slate-200 ring-1 ring-slate-600"
                          >
                            {ACTION_STATUSES.map((s) => (
                              <option key={s} value={s}>
                                {s}
                              </option>
                            ))}
                          </select>
                        </li>
                      ))}
                  </ul>
                )}
              </div>
            </div>

            <DecisionEvidencePanel
              evidence={
                JSON.parse(
                  history[history.length - 1]?.evidence || selected.evidence || '{}'
                ) as Record<string, unknown>
              }
              hash={history[history.length - 1]?.audit_hash ?? selected.audit_hash}
            />
          </div>
        </Panel>
      )}

      {newVersionFor && (
        <DecisionForm
          open
          onClose={() => setNewVersionFor(null)}
          onSaved={(rec) => {
            setToast(`Zapisano wersję ${rec.version} decyzji ${rec.decision_id}.`);
            void refresh();
          }}
          day={newVersionFor.scene_day}
          scope={newVersionFor.scope === 'kraj' ? 'kraj' : 'województwo'}
          voivodeshipCode={newVersionFor.voivodeship_code}
          recommendedLevel={newVersionFor.recommended_level}
          recommendedSpo={newVersionFor.spo_codes.split(',').filter(Boolean)}
          kis={newVersionFor.kis_at_decision}
          defaultTitle={newVersionFor.title}
          defaultText={newVersionFor.decision_text}
          previous={newVersionFor}
        />
      )}

      {actionFor && (
        <ActionModal
          decision={actionFor}
          onClose={() => setActionFor(null)}
          onSaved={() => {
            setToast('Dodano zadanie SPO.');
            void refresh();
          }}
        />
      )}

      <Toast message={toast} onDone={() => setToast(null)} />
      {actor.role === 'oficer dyżurny' && (
        <p className="text-xs text-slate-600">
          Rola „oficer dyżurny” może zapisywać projekty decyzji i prowadzić zadania, ale nie nadaje
          statusu „zatwierdzona”.
        </p>
      )}
    </div>
  );
}

function ActionModal({
  decision,
  onClose,
  onSaved,
}: {
  decision: DecisionRecord;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { actor, index } = useScenario();
  const codes = decision.spo_codes.split(',').filter(Boolean);
  const [spoCode, setSpoCode] = useState(codes[0] ?? 'SPO-3');
  const [text, setText] = useState('');
  const [owner, setOwner] = useState('');
  const [due, setDue] = useState(decision.scene_day);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async () => {
    if (text.trim().length < 3) {
      setError('Opisz zadanie (min. 3 znaki).');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await saveAction(
        {
          decision_id: decision.decision_id,
          spo_code: spoCode,
          action_text: text.trim(),
          owner: owner.trim(),
          due_day: due,
          status: 'nie rozpoczęto',
          note: '',
        },
        actor
      );
      onSaved();
      onClose();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal open title={`Zadanie do decyzji ${decision.decision_id}`} onClose={onClose}>
      <div className="space-y-4">
        <Field label="Procedura SPO">
          <select value={spoCode} onChange={(e) => setSpoCode(e.target.value)} className={inputClass}>
            {(codes.length ? codes : (index?.scene.spo ?? []).map((s) => s.code)).map((c) => (
              <option key={c} value={c}>
                {c} — {index?.spoByCode.get(c)?.name ?? ''}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Zadanie">
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            rows={3}
            className={inputClass}
          />
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Właściciel">
            <input value={owner} onChange={(e) => setOwner(e.target.value)} className={inputClass} />
          </Field>
          <Field label="Termin (doba sceny)">
            <input value={due} onChange={(e) => setDue(e.target.value)} className={inputClass} />
          </Field>
        </div>
        {error && <p className="text-sm text-red-400">{error}</p>}
        <div className="flex justify-end gap-2">
          <Button onClick={onClose}>Anuluj</Button>
          <Button variant="primary" onClick={() => void submit()} disabled={busy}>
            {busy ? 'Zapisywanie…' : 'Dodaj'}
          </Button>
        </div>
      </div>
    </Modal>
  );
}
