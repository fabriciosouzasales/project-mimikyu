import Link from "next/link";
import { AppShell } from "@/components/app-shell/app-shell";
import { ExpansoesTable } from "@/components/catalogo/expansoes-table";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { PageContainer, PageToolbar } from "@/components/ui/page";
import { getExpansoes, getGameOptions } from "@/lib/catalogo/queries";

/**
 * Lista de Expansões (`expansion`), com cadastro e edição (ADR-023, Queries
 * 2033/2034 — admin_create_expansion()/admin_update_expansion()). Suporta
 * filtro por Jogo via `?game=CODE` — usado pelo contador clicável de
 * Expansões na tela de Jogos. Mesmo padrão vertical de `/catalogo/jogos`,
 * mas sem seleção em massa/exclusão: só Game recebeu essa emenda ao
 * ADR-023.
 */
export default async function ExpansoesPage({
  searchParams,
}: {
  searchParams: Promise<{ game?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Expansões");
  if (denied) return denied;

  const { game } = await searchParams;
  const [expansoes, jogos] = await Promise.all([
    getExpansoes(supabase, game ? { gameCode: game } : undefined),
    getGameOptions(supabase),
  ]);
  const gameName = game ? (expansoes[0]?.gameName ?? game) : null;
  const defaultGameId = game ? jogos.find((j) => j.code === game)?.id : undefined;

  return (
    <AppShell title="Expansões">
      <PageContainer>
        {game && (
          <PageToolbar>
            <p className="text-xs text-muted-foreground">
              Filtrando por Jogo: <span className="text-foreground">{gameName}</span>{" "}
              <Link href="/catalogo/expansoes" className="underline-offset-2 hover:underline">
                Limpar filtro
              </Link>
            </p>
          </PageToolbar>
        )}

        <ExpansoesTable expansoes={expansoes} jogos={jogos} defaultGameId={defaultGameId} />
      </PageContainer>
    </AppShell>
  );
}
