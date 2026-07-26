import { AppShell } from "@/components/app-shell/app-shell";
import { JogosTable } from "@/components/catalogo/jogos-table";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { getJogos } from "@/lib/catalogo/queries";

/**
 * Lista de Jogos (`game`), com cadastro e edição (ADR-023, Queries
 * 2031/2032 — admin_create_game()/admin_update_game()). Título, botão de
 * criação e tabela vivem juntos em JogosTable (client component) — o botão
 * "Cadastrar novo jogo" fica fora do card da tabela, no padrão de ação
 * primária de página do Supabase (pedido de Fabrício, 2026-07-26).
 */
export default async function JogosPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Jogos");
  if (denied) return denied;

  const jogos = await getJogos(supabase);

  return (
    <AppShell title="Jogos">
      <div className="mx-auto max-w-6xl">
        <JogosTable jogos={jogos} />
      </div>
    </AppShell>
  );
}
