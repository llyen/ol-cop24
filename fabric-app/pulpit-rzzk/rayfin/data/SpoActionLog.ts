import { entity, role, text, date, uuid } from '@microsoft/rayfin-core';

/** Zadania wynikajace z uruchomionych SPO. */
@entity()
@role('authenticated', ['create', 'read'])
@role('authenticated', ['update', 'delete'], {
  policy: (claims, item) => claims.sub.eq(item.author_id),
})
export class SpoActionLog {
  @uuid() id!: string;
  /** decision_id decyzji, ktora uruchomila to SPO. */
  @text({ min: 3, max: 40 }) decision_id!: string;
  @text({ min: 3, max: 12 }) spo_code!: string;
  @text({ min: 3, max: 400 }) action_text!: string;
  @text({ max: 160 }) owner!: string;
  @text({ max: 10 }) due_day!: string;
  /** 'nie rozpoczeto' | 'w toku' | 'gotowe' | 'zablokowane'. */
  @text({ min: 3, max: 20 }) status!: string;
  @text({ max: 400 }) note!: string;
  @text({ max: 120 }) author_id!: string;
  @text({ max: 160 }) author_name!: string;
  @date() created_at!: Date;
}
