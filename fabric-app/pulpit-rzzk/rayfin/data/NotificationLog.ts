import { entity, role, text, int, date, uuid } from '@microsoft/rayfin-core';

/** Slad powiadomien: zwolanie RZZK, wezwania czlonkow, komunikaty do ludnosci. */
@entity()
@role('authenticated', ['create', 'read'])
export class NotificationLog {
  @uuid() id!: string;
  @text({ min: 3, max: 40 }) decision_id!: string;
  /** 'RZZK' | 'wojewodowie' | 'ludnosc' | 'media'. */
  @text({ min: 3, max: 40 }) channel!: string;
  @text({ max: 600 }) recipients!: string;
  @int() recipient_count!: number;
  @text({ min: 3, max: 160 }) subject!: string;
  @text({ min: 3, max: 1500 }) body!: string;
  @text({ min: 10, max: 10 }) scene_day!: string;
  @text({ max: 120 }) author_id!: string;
  @text({ max: 160 }) author_name!: string;
  @date() created_at!: Date;
}
