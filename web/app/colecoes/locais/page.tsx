import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { MapPin } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { LocationsView } from "@/components/colecoes/locais/locations-view";
import { getStorageOverview } from "@/lib/colecoes/storage-locations-queries";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser, getCachedUserProfile } from "@/lib/supabase/request-auth-cache";

export const metadata: Metadata = { title: "Meus locais · Coleções" };

/**
 * Meus locais — /colecoes/locais (WHERE-02 FRONTEND IMPLEMENTATION-01).
 *
 * Acesso: qualquer usuário autenticado (sem sessão → /login). A autorização
 * real está no banco: 5216–5219 exigem `auth.uid()`, resolvem o acervo do
 * chamador no servidor e não existem para `anon`; `storage_container_kind`
 * só expõe tipos ativos a `authenticated` (RLS). Nunca `service_role`.
 *
 * Uma rodada de leituras em paralelo (5219 locais + resumo, tipos). Gravações
 * em `actions.ts` (5216/5217/5218).
 */
export default async function LocaisPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) redirect("/login");

  void getCachedUserProfile().catch(() => {});

  const overview = await getStorageOverview(supabase);

  return (
    <AppShell title="Meus locais" icon={MapPin}>
      <LocationsView overview={overview} />
    </AppShell>
  );
}
