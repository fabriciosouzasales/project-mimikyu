import { AppShell } from "@/components/app-shell/app-shell";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { getJogos } from "@/lib/catalogo/queries";

/**
 * Lista de Jogos (`game`) — só 1 registro hoje ("Pokémon Trading Card Game").
 * Mesma linguagem visual da Visão Geral (Panel + tabela leve), aplicada
 * agora a este módulo dedicado.
 */
export default async function JogosPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Jogos");
  if (denied) return denied;

  const jogos = await getJogos(supabase);

  return (
    <AppShell title="Jogos">
      <div className="mx-auto max-w-6xl space-y-4">
        <h1 className="font-heading text-xl font-medium text-foreground">Jogos</h1>

        <Panel>
          <PanelHeader>
            <PanelTitle>Jogos cadastrados</PanelTitle>
          </PanelHeader>
          <PanelContent>
            {jogos.length === 0 ? (
              <div className="flex flex-col items-center gap-1 py-10 text-center">
                <p className="text-sm text-foreground">Nenhum jogo cadastrado ainda</p>
              </div>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-[11px] font-normal uppercase tracking-wide text-muted-foreground">
                    <th className="py-1.5 pr-3 font-normal">Jogo</th>
                    <th className="py-1.5 pr-3 font-normal">Código</th>
                    <th className="py-1.5 font-normal">Expansões</th>
                  </tr>
                </thead>
                <tbody>
                  {jogos.map((jogo) => (
                    <tr key={jogo.id} className="border-b border-border/60 last:border-b-0">
                      <td className="py-2 pr-3 text-foreground">{jogo.name}</td>
                      <td className="py-2 pr-3 text-muted-foreground">{jogo.code}</td>
                      <td className="py-2 text-muted-foreground">{jogo.totalExpansoes}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </PanelContent>
        </Panel>
      </div>
    </AppShell>
  );
}
