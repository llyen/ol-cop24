import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';

import { indexScene, type Scene, type SceneIndex } from '@/data/model';
import { useAuth } from '@/hooks/AuthContext';
import {
  listActions,
  listBriefs,
  listDecisions,
  listNotifications,
  type Actor,
  type BriefRecord,
  type DecisionRecord,
  type NotificationRecord,
  type SpoActionRecord,
  type UserRole,
} from '@/services/decisions';

interface ScenarioValue {
  index: SceneIndex | null;
  loading: boolean;
  error: string | null;
  /** Indeks dnia sceny (0..13). */
  dayIndex: number;
  day: string;
  setDayIndex: (i: number) => void;
  playing: boolean;
  togglePlay: () => void;
  speed: number;
  setSpeed: (s: number) => void;
  actor: Actor;
  setRole: (role: UserRole) => void;
  setVoivodeship: (code: string) => void;
  decisions: DecisionRecord[];
  actions: SpoActionRecord[];
  briefs: BriefRecord[];
  notifications: NotificationRecord[];
  refresh: () => Promise<void>;
  writebackError: string | null;
}

const ScenarioContext = createContext<ScenarioValue | undefined>(undefined);

const ROLE_KEY = 'rzzk.role';
const VOIV_KEY = 'rzzk.voivodeship';

export function ScenarioProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const [index, setIndex] = useState<SceneIndex | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [dayIndex, setDayIndexState] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [speed, setSpeed] = useState(1800);
  const [role, setRoleState] = useState<UserRole>(
    () => (localStorage.getItem(ROLE_KEY) as UserRole) || 'Dyrektor RCB'
  );
  const [voivodeship, setVoivodeshipState] = useState<string>(
    () => localStorage.getItem(VOIV_KEY) || ''
  );
  const [decisions, setDecisions] = useState<DecisionRecord[]>([]);
  const [actions, setActions] = useState<SpoActionRecord[]>([]);
  const [briefs, setBriefs] = useState<BriefRecord[]>([]);
  const [notifications, setNotifications] = useState<NotificationRecord[]>([]);
  const [writebackError, setWritebackError] = useState<string | null>(null);
  const timer = useRef<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetch(`${import.meta.env.BASE_URL}data/scene.json`)
      .then((r) => {
        if (!r.ok) throw new Error(`Nie udało się wczytać sceny (HTTP ${r.status}).`);
        return r.json() as Promise<Scene>;
      })
      .then((scene) => {
        if (cancelled) return;
        const idx = indexScene(scene);
        setIndex(idx);
        // Start na dniu kulminacji - demo od razu pokazuje sytuację decyzyjną.
        const peak = idx.scene.country.reduce(
          (best, c, i) => (c.maxKis > idx.scene.country[best].maxKis ? i : best),
          0
        );
        setDayIndexState(Math.max(peak - 2, 0));
      })
      .catch((e: unknown) => {
        if (!cancelled) setError(e instanceof Error ? e.message : String(e));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const refresh = useCallback(async () => {
    try {
      const [d, a, b, n] = await Promise.all([
        listDecisions(),
        listActions(),
        listBriefs(),
        listNotifications(),
      ]);
      setDecisions(d);
      setActions(a);
      setBriefs(b);
      setNotifications(n);
      setWritebackError(null);
    } catch (e: unknown) {
      setWritebackError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!playing || !index) return;
    timer.current = window.setInterval(() => {
      setDayIndexState((i) => (i + 1 >= index.days.length ? 0 : i + 1));
    }, speed);
    return () => {
      if (timer.current) window.clearInterval(timer.current);
    };
  }, [playing, speed, index]);

  const setDayIndex = useCallback((i: number) => {
    setPlaying(false);
    setDayIndexState(i);
  }, []);

  const setRole = useCallback((r: UserRole) => {
    setRoleState(r);
    localStorage.setItem(ROLE_KEY, r);
  }, []);

  const setVoivodeship = useCallback((code: string) => {
    setVoivodeshipState(code);
    localStorage.setItem(VOIV_KEY, code);
  }, []);

  const actor: Actor = useMemo(
    () => ({
      id: user?.id ?? 'local-user',
      name: user?.name ?? user?.email ?? 'Użytkownik demonstracyjny',
      role,
      voivodeshipCode: voivodeship,
    }),
    [user, role, voivodeship]
  );

  const value: ScenarioValue = useMemo(
    () => ({
      index,
      loading,
      error,
      dayIndex,
      day: index ? index.days[dayIndex] : '',
      setDayIndex,
      playing,
      togglePlay: () => setPlaying((p) => !p),
      speed,
      setSpeed,
      actor,
      setRole,
      setVoivodeship,
      decisions,
      actions,
      briefs,
      notifications,
      refresh,
      writebackError,
    }),
    [
      index,
      loading,
      error,
      dayIndex,
      setDayIndex,
      playing,
      speed,
      actor,
      setRole,
      setVoivodeship,
      decisions,
      actions,
      briefs,
      notifications,
      refresh,
      writebackError,
    ]
  );

  return <ScenarioContext.Provider value={value}>{children}</ScenarioContext.Provider>;
}

export function useScenario(): ScenarioValue {
  const ctx = useContext(ScenarioContext);
  if (!ctx) throw new Error('useScenario musi być użyte wewnątrz ScenarioProvider');
  return ctx;
}
