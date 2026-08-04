import { DecisionLog } from './DecisionLog.js';
import { SpoActionLog } from './SpoActionLog.js';
import { BriefRequest } from './BriefRequest.js';
import { NotificationLog } from './NotificationLog.js';

export type AppSchema = {
  DecisionLog: DecisionLog;
  SpoActionLog: SpoActionLog;
  BriefRequest: BriefRequest;
  NotificationLog: NotificationLog;
};

export const schema = [DecisionLog, SpoActionLog, BriefRequest, NotificationLog];
