import { AppShell } from "@/components/app-shell/app-shell";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { getExpansoes } from "@/lib/catalogo/queries";

/** Lista de Expansões (`expansion`) — só 1 registro hoje ("ME" — Mega Evolution). */
export default async function ExpansoesPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Expansões");
  if (denied) return denied;

  const expansoes = await getExpansoes(supabase);

  return (
    <AppShell title="Expansões">
      <div className="mx-auto max-w-6xl space-y-4">
        <h1 className="font-heading text-xl font-medium text-foreground">Expansões</h1>

        <Panel>
          <PanelHeader>
            <PanelTitle>Expansões cadastradas</PanelTitle>
          </PanelHeader>
          <PanelContent>
            {expansoes.length === 0 ? (
              <div className="flex flex-col items-center gap-1 py-10 text-center">
                <p className="text-sm text-foreground">Nenhuma expansão cadastrada ainda</p>
              </div>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-[11px] font-normal uppercase tracking-wide text-muted-foreground">
                    <th className="py-1.5 pr-3 font-normal">Expansão</th>
                    <th className="py-1.5 pr-3 font-normal">Código</th>
                    <th className="py-1.5 pr-3 font-normal">Jogo</th>
                    <th className="py-1.5 pr-3 font-normal">Ordem</th>
                    <th className="py-1.5 font-normal">Card Sets</th>
                  </tr>
                </thead>
                <tbody>
                  {expansoes.map((expansao) => (
                    <tr key={expansao.id} className="border-b border-border/60 last:border-b-0">
                      <td className="py-2 pr-3 text-foreground">{expansao.name}</td>
                      <td className="py-2 pr-3 text-muted-foreground">{expansao.code}</td>
                      <td className="py-2 pr-3 text-muted-foreground">{expansao.gameName}</td>
                      <td className="py-2 pr-3 text-muted-foreground">{expansao.releaseOrder}</td>
                      <td className="py-2 text-muted-foreground">{expansao.totalCardSets}</td>
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
