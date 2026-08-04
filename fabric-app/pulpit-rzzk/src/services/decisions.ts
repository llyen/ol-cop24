import { getRayfinClient, isLocalBackend } from './rayfinClient';
import { auditHash } from '@/data/model';

/**
 * Zapis zwrotny COP-24.
 *
 * Trzy zasady z APP_SPEC.md:
 * 1. Decyzji sie nie usuwa - korekta to nowa wersja z tym samym decision_id.
 * 2. Kazda decyzja niesie migawke przeslanek i skrot kontrolny (audit_hash).
 * 3. Status "zatwierdzona" moze nadac wylacznie Dyrektor RCB albo minister wiodacy.
 *
 * Bez skonfigurowanego backendu (dev lokalny) dane trafiaja do pamieci,
 * zeby aplikacje dalo sie zademonstrowac takze offline.
 */

export type UserRole = 'Dyrektor RCB' | 'oficer dyżurny' | 'wojewoda' | 'minister wiodący';

export const USER_ROLES: UserRole[] = [
  'Dyrektor RCB',
  'oficer dyżurny',
  'wojewoda',
  'minister wiodący',
];

export const APPROVING_ROLES: UserRole[] = ['Dyrektor RCB', 'minister wiodący'];

export interface DecisionRecord {
  id: string;
  decision_id: string;
  version: number;
  supersedes_version: number;
  scene_day: string;
  scope: string;
  voivodeship_code: string;
  title: string;
  decision_text: string;
  recommended_level: string;
  chosen_level: string;
  spo_codes: string;
  status: string;
  kis_at_decision: number;
  evidence: string;
  audit_hash: string;
  author_id: string;
  author_name: string;
  author_role: string;
  created_at: Date;
}

export interface SpoActionRecord {
  id: string;
  decision_id: string;
  spo_code: string;
  action_text: string;
  owner: string;
  due_day: string;
  status: string;
  note: string;
  author_id: string;
  author_name: string;
  created_at: Date;
}

export interface BriefRecord {
  id: string;
  scene_day: string;
  scope: string;
  voivodeship_code: string;
  audience: string;
  format: string;
  note: string;
  status: string;
  author_id: string;
  author_name: string;
  created_at: Date;
}

export interface NotificationRecord {
  id: string;
  decision_id: string;
  channel: string;
  recipients: string;
  recipient_count: number;
  subject: string;
  body: string;
  scene_day: string;
  author_id: string;
  author_name: string;
  created_at: Date;
}

const memory = {
  decisions: [] as DecisionRecord[],
  actions: [] as SpoActionRecord[],
  briefs: [] as BriefRecord[],
  notifications: [] as NotificationRecord[],
};

export interface Actor {
  id: string;
  name: string;
  role: UserRole;
  /** Kod wojewodztwa, jesli rola jest wojewodzka. Pusty = zakres krajowy. */
  voivodeshipCode: string;
}

export interface DecisionDraft {
  scene_day: string;
  scope: 'kraj' | 'województwo';
  voivodeship_code: string;
  title: string;
  decision_text: string;
  recommended_level: string;
  chosen_level: string;
  spo_codes: string[];
  status: 'projekt' | 'zatwierdzona' | 'odrzucona';
  kis_at_decision: number;
  evidence: Record<string, unknown>;
}

export interface ValidationResult {
  ok: boolean;
  errors: string[];
}

/**
 * Walidacja jest w warstwie domenowej, a nie w komponencie, zeby te same reguly
 * dalo sie sprawdzic testem. Baza wymusza dlugosci pol, ale komunikaty po polsku
 * muszaja powstac tutaj.
 */
export function validateDecision(draft: DecisionDraft, actor: Actor): ValidationResult {
  const errors: string[] = [];
  if (draft.title.trim().length < 3) errors.push('Tytuł decyzji musi mieć co najmniej 3 znaki.');
  if (draft.decision_text.trim().length < 20)
    errors.push('Treść decyzji musi mieć co najmniej 20 znaków — to zapis dla protokołu.');
  if (draft.decision_text.length > 2000) errors.push('Treść decyzji nie może przekraczać 2000 znaków.');
  if (!draft.chosen_level) errors.push('Wybierz poziom reagowania.');
  if (draft.scope === 'województwo' && !draft.voivodeship_code)
    errors.push('Dla zakresu wojewódzkiego wskaż województwo.');
  if (
    actor.role === 'wojewoda' &&
    draft.scope === 'województwo' &&
    actor.voivodeshipCode &&
    draft.voivodeship_code !== actor.voivodeshipCode
  )
    errors.push('Wojewoda może zapisywać decyzje wyłącznie dla własnego województwa.');
  if (actor.role === 'wojewoda' && draft.scope === 'kraj')
    errors.push('Decyzję o zakresie krajowym zapisuje RCB albo minister wiodący.');
  if (draft.status === 'zatwierdzona' && !APPROVING_ROLES.includes(actor.role))
    errors.push('Status „zatwierdzona” może nadać wyłącznie Dyrektor RCB albo minister wiodący.');
  if (draft.spo_codes.length === 0) errors.push('Wskaż co najmniej jedną procedurę SPO.');
  return { ok: errors.length === 0, errors };
}

export function buildEvidenceHash(draft: DecisionDraft): string {
  return auditHash(
    JSON.stringify({
      d: draft.scene_day,
      s: draft.scope,
      v: draft.voivodeship_code,
      l: draft.chosen_level,
      k: draft.kis_at_decision,
      e: draft.evidence,
    })
  );
}

function newDecisionId(day: string): string {
  const stamp = day.replace(/-/g, '').slice(4);
  const rand = Math.random().toString(36).slice(2, 7).toUpperCase();
  return `DEC-${stamp}-${rand}`;
}

export async function listDecisions(): Promise<DecisionRecord[]> {
  if (isLocalBackend()) return [...memory.decisions];
  const client = getRayfinClient();
  const rows = await client.data.DecisionLog.select([
    'id',
    'decision_id',
    'version',
    'supersedes_version',
    'scene_day',
    'scope',
    'voivodeship_code',
    'title',
    'decision_text',
    'recommended_level',
    'chosen_level',
    'spo_codes',
    'status',
    'kis_at_decision',
    'evidence',
    'audit_hash',
    'author_id',
    'author_name',
    'author_role',
    'created_at',
  ])
    .orderBy({ created_at: 'desc' })
    .execute();
  return rows as unknown as DecisionRecord[];
}

/**
 * Zapisuje nowa decyzje albo nowa wersje istniejacej.
 * previous = decyzja, ktora jest korygowana (wtedy decision_id jest zachowany).
 */
export async function saveDecision(
  draft: DecisionDraft,
  actor: Actor,
  previous?: DecisionRecord | null
): Promise<DecisionRecord> {
  const validation = validateDecision(draft, actor);
  if (!validation.ok) throw new Error(validation.errors.join(' '));

  const record: DecisionRecord = {
    id: crypto.randomUUID(),
    decision_id: previous?.decision_id ?? newDecisionId(draft.scene_day),
    version: (previous?.version ?? 0) + 1,
    supersedes_version: previous?.version ?? 0,
    scene_day: draft.scene_day,
    scope: draft.scope,
    voivodeship_code: draft.voivodeship_code,
    title: draft.title.trim(),
    decision_text: draft.decision_text.trim(),
    recommended_level: draft.recommended_level,
    chosen_level: draft.chosen_level,
    spo_codes: draft.spo_codes.join(','),
    status: draft.status,
    kis_at_decision: draft.kis_at_decision,
    evidence: JSON.stringify(draft.evidence).slice(0, 2000),
    audit_hash: buildEvidenceHash(draft),
    author_id: actor.id,
    author_name: actor.name,
    author_role: actor.role,
    created_at: new Date(),
  };

  if (isLocalBackend()) {
    memory.decisions.unshift(record);
    return record;
  }

  const client = getRayfinClient();
  const { id: _ignored, ...payload } = record;
  void _ignored;
  const saved = await client.data.DecisionLog.create(payload);
  return saved as unknown as DecisionRecord;
}

export async function listActions(): Promise<SpoActionRecord[]> {
  if (isLocalBackend()) return [...memory.actions];
  const client = getRayfinClient();
  const rows = await client.data.SpoActionLog.select([
    'id',
    'decision_id',
    'spo_code',
    'action_text',
    'owner',
    'due_day',
    'status',
    'note',
    'author_id',
    'author_name',
    'created_at',
  ])
    .orderBy({ created_at: 'desc' })
    .execute();
  return rows as unknown as SpoActionRecord[];
}

export async function saveAction(
  input: Omit<SpoActionRecord, 'id' | 'created_at' | 'author_id' | 'author_name'>,
  actor: Actor
): Promise<SpoActionRecord> {
  const record: SpoActionRecord = {
    ...input,
    id: crypto.randomUUID(),
    author_id: actor.id,
    author_name: actor.name,
    created_at: new Date(),
  };
  if (isLocalBackend()) {
    memory.actions.unshift(record);
    return record;
  }
  const client = getRayfinClient();
  const { id: _ignored, ...payload } = record;
  void _ignored;
  const saved = await client.data.SpoActionLog.create(payload);
  return saved as unknown as SpoActionRecord;
}

export async function updateActionStatus(id: string, status: string): Promise<void> {
  if (isLocalBackend()) {
    const row = memory.actions.find((a) => a.id === id);
    if (row) row.status = status;
    return;
  }
  const client = getRayfinClient();
  await client.data.SpoActionLog.update({ id }, { status });
}

export async function listBriefs(): Promise<BriefRecord[]> {
  if (isLocalBackend()) return [...memory.briefs];
  const client = getRayfinClient();
  const rows = await client.data.BriefRequest.select([
    'id',
    'scene_day',
    'scope',
    'voivodeship_code',
    'audience',
    'format',
    'note',
    'status',
    'author_id',
    'author_name',
    'created_at',
  ])
    .orderBy({ created_at: 'desc' })
    .execute();
  return rows as unknown as BriefRecord[];
}

export async function saveBrief(
  input: Omit<BriefRecord, 'id' | 'created_at' | 'author_id' | 'author_name'>,
  actor: Actor
): Promise<BriefRecord> {
  const record: BriefRecord = {
    ...input,
    id: crypto.randomUUID(),
    author_id: actor.id,
    author_name: actor.name,
    created_at: new Date(),
  };
  if (isLocalBackend()) {
    memory.briefs.unshift(record);
    return record;
  }
  const client = getRayfinClient();
  const { id: _ignored, ...payload } = record;
  void _ignored;
  const saved = await client.data.BriefRequest.create(payload);
  return saved as unknown as BriefRecord;
}

export async function listNotifications(): Promise<NotificationRecord[]> {
  if (isLocalBackend()) return [...memory.notifications];
  const client = getRayfinClient();
  const rows = await client.data.NotificationLog.select([
    'id',
    'decision_id',
    'channel',
    'recipients',
    'recipient_count',
    'subject',
    'body',
    'scene_day',
    'author_id',
    'author_name',
    'created_at',
  ])
    .orderBy({ created_at: 'desc' })
    .execute();
  return rows as unknown as NotificationRecord[];
}

export async function saveNotification(
  input: Omit<NotificationRecord, 'id' | 'created_at' | 'author_id' | 'author_name'>,
  actor: Actor
): Promise<NotificationRecord> {
  const record: NotificationRecord = {
    ...input,
    id: crypto.randomUUID(),
    author_id: actor.id,
    author_name: actor.name,
    created_at: new Date(),
  };
  if (isLocalBackend()) {
    memory.notifications.unshift(record);
    return record;
  }
  const client = getRayfinClient();
  const { id: _ignored, ...payload } = record;
  void _ignored;
  const saved = await client.data.NotificationLog.create(payload);
  return saved as unknown as NotificationRecord;
}

/** Ostatnia wersja kazdej decyzji - widok domyslny rejestru. */
export function latestVersions(rows: DecisionRecord[]): DecisionRecord[] {
  const byId = new Map<string, DecisionRecord>();
  for (const row of rows) {
    const current = byId.get(row.decision_id);
    if (!current || row.version > current.version) byId.set(row.decision_id, row);
  }
  return [...byId.values()].sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  );
}

export function versionsOf(rows: DecisionRecord[], decisionId: string): DecisionRecord[] {
  return rows.filter((r) => r.decision_id === decisionId).sort((a, b) => a.version - b.version);
}
