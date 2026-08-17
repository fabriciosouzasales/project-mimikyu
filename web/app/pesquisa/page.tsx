import { redirect } from "next/navigation";
import { Search } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { PesquisaView } from "@/components/pesquisa/pesquisa-view";
import { createClient } from "@/lib/supabase/server";

/**
 * Pesquisa avançada de cartas — Incremento "Pesquisa Global de Cartas"
 * (2026-08-17, ver ADR-030). Rota de produto para qualquer usuário
 * autenticado, deliberadamente FORA de `/catalogo` (que é administrativo,
 * ADR-022) — mesma guarda simples de `/perfil` (checa sessão, redireciona
 * para /login sem sessão), sem `requireCatalogoAdmin()`.
 *
 * Estado (busca, filtros, paginação) vive inteiramente na URL — `PesquisaView`
 * é Client Component e lê/escreve via `useSearchParams`/`useRouter`, para que
 * a página inicial (`searchParams` do Server Component) e qualquer navegação
 * subsequente fiquem sempre em sincronia com o que está na barra de endereço.
 */
export default async function PesquisaPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  return (
    <AppShell title="Pesquisa avançada" icon={Search}>
      <PesquisaView />
    </AppShell>
  );
}
