import { useMemo, useState } from 'react';

import {
  cascadeSignals,
  formatNumber,
  levelBadgeClass,
  levelRank,
  ESCALATION_LEVELS,
  type SceneIndex,
} from '@/data/model';
import { useScenario } from '@/hooks/ScenarioContext';
import {
  buildEvidenceHash,
  saveDecision,
  validateDecision,
  APPROVING_ROLES,
  type DecisionDraft,
  type DecisionRecord,
} from '@/services/decisions';
import { Badge, Button, Field, Modal, Panel, inputClass } from '@/components/ui';

/** Migawka przeslanek - to samo, co trafia do audit_hash. */
export function buildEvidence(
  index: SceneIndex,
  day: string,
  voivCode: string
): Record<string, unknown> {
  const country = index.countryByDay.get(day);
  const voiv = (index.voivByDay.get(day) ?? []).find((r) => r.v === voivCode);
  const base = voiv ?? country;
  return {
    doba: day,
    zakres: voivCode ? index.voivByCode.get(voivCode)?.name : 'kraj',
    kis: base?.kis ?? 0,
    maksKis: base?.maxKis ?? 0,
    gminyAlarm: base?.alarmGminas ?? 0,
    zgloszenia: base?.inc ?? 0,
    bezPradu: base?.off ?? 0,
    ewakuowani: base?.evac ?? 0,
    minPokrycie: base?.minCov ?? null,
    kaskada: base ? cascadeSignals(base).filter((c) => c.active).map((c) => c.label) : [],
    dezinformacja: country?.disinfo ?? 0,
  };
}

export function DecisionEvidencePanel({
  evidence,
  hash,
}: {
  evidence: Record<string, unknown>;
  hash?: string;
}) {
  return (
    <Panel title="Przesłanki decyzji" subtitle="migawka obrazu sytuacji z chwili zapisu">
      <dl className="grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm sm:grid-cols-3">
        {Object.entries(evidence).map(([k, v]) => (
          <div key={k} className="rounded-lg bg-slate-50 px-3 py-2">
            <dt className="text-[11px] uppercase tracking-wide text-slate-500">{k}</dt>
            <dd className="tabular-nums text-slate-900">
              {Array.isArray(v)
                ? v.length
                  ? v.join(', ')
                  : '—'
                : typeof v === 'number'
                  ? formatNumber(v)
                  : String(v ?? '—')}
            </dd>
          </div>
        ))}
      </dl>
      {hash && (
        <p className="mt-3 font-mono text-[11px] text-slate-500">
          Skrót kontrolny przesłanek: <span className="text-gov">{hash}</span>
        </p>
      )}
    </Panel>
  );
}

export function SpoChecklist({
  codes,
  selected,
  onToggle,
  index,
}: {
  codes: string[];
  selected: string[];
  onToggle: (code: string) => void;
  index: SceneIndex;
}) {
  return (
    <ul className="space-y-1.5">
      {codes.map((code) => {
        const spo = index.spoByCode.get(code);
        const on = selected.includes(code);
        return (
          <li key={code}>
            <button
              type="button"
              onClick={() => onToggle(code)}
              className={`flex w-full items-start gap-3 rounded-lg px-3 py-2 text-left text-sm ring-1 transition-colors ${
                on
                  ? 'bg-gov/10 text-gov-dark ring-gov/40'
                  : 'bg-slate-50 text-slate-700 ring-slate-200 hover:bg-slate-50'
              }`}
            >
              <span
                className={`mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded border text-[10px] ${
                  on ? 'border-gov bg-gov text-white' : 'border-slate-300'
                }`}
              >
                {on ? '✓' : ''}
              </span>
              <span>
                <span className="font-medium">{code}</span>
                <span className="ml-2 text-xs text-slate-500">{spo?.name ?? ''}</span>
              </span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}

export interface DecisionFormProps {
  open: boolean;
  onClose: () => void;
  onSaved: (record: DecisionRecord) => void;
  day: string;
  scope: 'kraj' | 'województwo';
  voivodeshipCode: string;
  recommendedLevel: string;
  recommendedSpo: string[];
  kis: number;
  defaultTitle?: string;
  defaultText?: string;
  /** Poprzednia wersja - wtedy formularz tworzy kolejna wersje tej samej decyzji. */
  previous?: DecisionRecord | null;
}

export function DecisionForm(props: DecisionFormProps) {
  const { index, actor } = useScenario();
  const {
    open,
    onClose,
    onSaved,
    day,
    scope,
    voivodeshipCode,
    recommendedLevel,
    recommendedSpo,
    kis,
    previous,
  } = props;

  const [title, setTitle] = useState(props.defaultTitle ?? '');
  const [text, setText] = useState(props.defaultText ?? '');
  const [level, setLevel] = useState(previous?.chosen_level ?? recommendedLevel);
  const [spo, setSpo] = useState<string[]>(
    previous ? previous.spo_codes.split(',').filter(Boolean) : recommendedSpo
  );
  const [status, setStatus] = useState<'projekt' | 'zatwierdzona' | 'odrzucona'>('projekt');
  const [busy, setBusy] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);

  const evidence = useMemo(
    () => (index ? buildEvidence(index, day, voivodeshipCode) : {}),
    [index, day, voivodeshipCode]
  );

  const draft: DecisionDraft = {
    scene_day: day,
    scope,
    voivodeship_code: voivodeshipCode,
    title,
    decision_text: text,
    recommended_level: recommendedLevel,
    chosen_level: level,
    spo_codes: spo,
    status,
    kis_at_decision: kis,
    evidence,
  };

  const deviation = levelRank(level) - levelRank(recommendedLevel);
  const canApprove = APPROVING_ROLES.includes(actor.role);

  const submit = async () => {
    const check = validateDecision(draft, actor);
    if (!check.ok) {
      setErrors(check.errors);
      return;
    }
    setBusy(true);
    setErrors([]);
    try {
      const saved = await saveDecision(draft, actor, previous);
      onSaved(saved);
      onClose();
      setTitle('');
      setText('');
    } catch (e: unknown) {
      setErrors([e instanceof Error ? e.message : String(e)]);
    } finally {
      setBusy(false);
    }
  };

  if (!index) return null;
  const allSpo = [...new Set([...recommendedSpo, ...index.scene.spo.map((s) => s.code)])];

  return (
    <Modal
      open={open}
      wide
      title={previous ? `Nowa wersja decyzji ${previous.decision_id}` : 'Zapisz decyzję'}
      onClose={onClose}
    >
      <div className="space-y-4">
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <Badge className={levelBadgeClass(recommendedLevel)}>
            rekomendacja systemu: {recommendedLevel}
          </Badge>
          <span className="text-slate-500">KIS {kis}</span>
          <span className="text-slate-500">· doba {day}</span>
          <span className="text-slate-500">· {actor.role}</span>
        </div>

        <Field label="Tytuł decyzji">
          <input value={title} onChange={(e) => setTitle(e.target.value)} className={inputClass} />
        </Field>

        <Field
          label="Treść decyzji"
          hint="Minimum 20 znaków. Zapis trafia do protokołu i nie jest usuwalny."
        >
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            rows={5}
            className={inputClass}
          />
        </Field>

        <div className="grid gap-4 md:grid-cols-2">
          <Field label="Wybrany poziom reagowania">
            <select value={level} onChange={(e) => setLevel(e.target.value)} className={inputClass}>
              {ESCALATION_LEVELS.map((l) => (
                <option key={l} value={l}>
                  {l}
                </option>
              ))}
            </select>
          </Field>
          <Field
            label="Status"
            hint={canApprove ? undefined : 'Twoja rola może zapisać wyłącznie projekt.'}
          >
            <select
              value={status}
              onChange={(e) => setStatus(e.target.value as typeof status)}
              className={inputClass}
            >
              <option value="projekt">projekt</option>
              <option value="zatwierdzona" disabled={!canApprove}>
                zatwierdzona
              </option>
              <option value="odrzucona">odrzucona</option>
            </select>
          </Field>
        </div>

        {deviation !== 0 && (
          <p className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-800 ring-1 ring-amber-600/30">
            Wybrany poziom jest {deviation > 0 ? 'wyższy' : 'niższy'} niż rekomendacja systemu.
            Odstępstwo zostanie zapisane razem z przesłankami — opisz powód w treści decyzji.
          </p>
        )}

        <div>
          <p className="mb-2 text-xs font-medium uppercase tracking-wide text-slate-500">
            Uruchamiane procedury SPO
          </p>
          <SpoChecklist
            codes={allSpo}
            selected={spo}
            index={index}
            onToggle={(code) =>
              setSpo((prev) => (prev.includes(code) ? prev.filter((c) => c !== code) : [...prev, code]))
            }
          />
        </div>

        <DecisionEvidencePanel evidence={evidence} hash={buildEvidenceHash(draft)} />

        {errors.length > 0 && (
          <ul className="space-y-1 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700 ring-1 ring-red-600/30">
            {errors.map((e) => (
              <li key={e}>• {e}</li>
            ))}
          </ul>
        )}

        <div className="flex justify-end gap-2">
          <Button onClick={onClose}>Anuluj</Button>
          <Button variant="primary" onClick={() => void submit()} disabled={busy}>
            {busy ? 'Zapisywanie…' : previous ? 'Zapisz nową wersję' : 'Zapisz decyzję'}
          </Button>
        </div>
      </div>
    </Modal>
  );
}
