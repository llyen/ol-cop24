import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';

import { AuthPage } from '@/components/AuthPage';
import { Layout } from '@/components/Layout';
import { useAuth } from '@/hooks/AuthContext';
import { ScenarioProvider, useScenario } from '@/hooks/ScenarioContext';
import { SituationPage } from '@/pages/SituationPage';
import { VoivodeshipPage } from '@/pages/VoivodeshipPage';
import { RecommendationsPage } from '@/pages/RecommendationsPage';
import { DecisionsPage } from '@/pages/DecisionsPage';
import { ConveneRzzkPage } from '@/pages/ConveneRzzkPage';

function AuthGuard({
  children,
  requireAuth,
}: {
  children: React.ReactNode;
  requireAuth: boolean;
}) {
  const { isAuthenticated, loading } = useAuth();

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100 text-slate-600">
        Uwierzytelnianie…
      </div>
    );
  }

  if (requireAuth && !isAuthenticated) return <Navigate to="/auth" replace />;
  if (!requireAuth && isAuthenticated) return <Navigate to="/" replace />;

  return <>{children}</>;
}

function SceneGate({ children }: { children: React.ReactNode }) {
  const { loading, error } = useScenario();
  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100 text-slate-600">
        Wczytywanie sceny COP-24…
      </div>
    );
  }
  if (error) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100 px-6 text-center text-red-700">
        {error}
      </div>
    );
  }
  return <>{children}</>;
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <AuthGuard requireAuth>
      <ScenarioProvider>
        <SceneGate>
          <Layout>{children}</Layout>
        </SceneGate>
      </ScenarioProvider>
    </AuthGuard>
  );
}

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route
          path="/auth"
          element={
            <AuthGuard requireAuth={false}>
              <AuthPage />
            </AuthGuard>
          }
        />
        <Route
          path="/"
          element={
            <Shell>
              <SituationPage />
            </Shell>
          }
        />
        <Route
          path="/wojewodztwo"
          element={
            <Shell>
              <VoivodeshipPage />
            </Shell>
          }
        />
        <Route
          path="/rekomendacje"
          element={
            <Shell>
              <RecommendationsPage />
            </Shell>
          }
        />
        <Route
          path="/decyzje"
          element={
            <Shell>
              <DecisionsPage />
            </Shell>
          }
        />
        <Route
          path="/rzzk"
          element={
            <Shell>
              <ConveneRzzkPage />
            </Shell>
          }
        />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;
