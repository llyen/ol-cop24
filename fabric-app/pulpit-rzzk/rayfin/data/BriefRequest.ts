import { entity, role, text, date, uuid } from '@microsoft/rayfin-core';

/** Zamowienie noty/briefu dla decydenta (np. brief dla Prezesa Rady Ministrow). */
@entity()
@role('authenticated', ['create', 'read'])
@role('authenticated', ['update', 'delete'], {
  policy: (claims, item) => claims.sub.eq(item.author_id),
})
export class BriefRequest {
  @uuid() id!: string;
  @text({ min: 10, max: 10 }) scene_day!: string;
  @text({ min: 4, max: 20 }) scope!: string;
  @text({ max: 4 }) voivodeship_code!: string;
  /** Odbiorca: 'RZZK' | 'Prezes RM' | 'minister wiodacy' | 'wojewoda'. */
  @text({ min: 3, max: 60 }) audience!: string;
  /** 'nota 1 strona' | 'prezentacja' | 'komunikat prasowy'. */
  @text({ min: 3, max: 40 }) format!: string;
  @text({ max: 600 }) note!: string;
  @text({ min: 3, max: 20 }) status!: string;
  @text({ max: 120 }) author_id!: string;
  @text({ max: 160 }) author_name!: string;
  @date() created_at!: Date;
}
