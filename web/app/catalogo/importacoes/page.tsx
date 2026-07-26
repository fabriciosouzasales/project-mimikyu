import { AppShell } from "@/components/app-shell/app-shell";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { StateBadge } from "@/components/catalogo/state-badge";
import type { StateTone } from "@/components/catalogo/state-badge";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { getImportacoes } from "@/lib/catalogo/queries";

const STATUS_LABEL: Record<string, { texto: string; tone: StateTone }> = {
  COMPLETED: { texto: "Concluída", tone: "success" },
  COMPLETED_WITH_ERRORS: { texto: "Com falhas", tone: "warning" },
  FAILED: { texto: "Falhou", tone: "danger" },
  RUNNING: { texto: "Em andamento", tone: "muted" },
  PENDING: { texto: "Pendente", tone: "muted" },
  CANCELLED: { texto: "Cancelada", tone: "muted" },
};

const RUN_TYPE_LABEL: Record<string, string> = {
  MISSING_ONLY: "Apenas ausentes",
  REFRESH_EXISTING: "Atualizar existentes",
  RETRY_FAILURES: "Repetir falhas",
  SINGLE_CARD: "Carta única",
  FULL_CARD_SET: "Card Set completo",
};

/**
 * Histórico completo de execuções de importação — versão sem `limit` do
 * bloco "Atividade recente" da Visão Geral, com mais colunas (tipo, fonte,
 * idioma) por ser o destino dedicado desta informação.
 */
export default async function ImportacoesPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Histórico de importações");
  if (denied) return denied;

  const importacoes = await getImportacoes(supabase);

  return (
    <AppShell title="Histórico de importações">
      <div className="mx-auto max-w-6xl space-y-4">
        <h1 className="font-heading text-xl font-medium text-foreground">Histórico de importações</h1>

        <Panel>
          <PanelHeader>
            <PanelTitle>Execuções registradas</PanelTitle>
          </PanelHeader>
          <PanelContent>
            {importacoes.length === 0 ? (
              <div className="flex flex-col items-center gap-1 py-10 text-center">
                <p className="text-sm text-foreground">Nenhuma execução registrada ainda</p>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-border text-left text-[11px] font-normal uppercase tracking-wide text-muted-foreground">
                      <th className="py-1.5 pr-3 font-normal">Execução</th>
                      <th className="py-1.5 pr-3 font-normal">Tipo</th>
                      <th className="py-1.5 pr-3 font-normal">Card Set</th>
                      <th className="py-1.5 pr-3 font-normal">Fonte</th>
                      <th className="py-1.5 pr-3 font-normal">Status</th>
                      <th className="py-1.5 pr-3 font-normal">Resultado</th>
                      <th className="py-1.5 font-normal">Data</th>
                    </tr>
                  </thead>
                  <tbody>
                    {importacoes.map((run) => {
                      const status = STATUS_LABEL[run.status] ?? { texto: run.status, tone: "muted" as const };
                      return (
                        <tr key={run.id} className="border-b border-border/60 last:border-b-0">
                          <td className="py-2 pr-3 text-[11px] text-muted-foreground">{run.runCode}</td>
                          <td className="py-2 pr-3 text-muted-foreground">
                            {RUN_TYPE_LABEL[run.runType] ?? run.runType}
                          </td>
                          <td className="py-2 pr-3 text-foreground">{run.cardSetCode ?? "—"}</td>
                          <td className="py-2 pr-3 text-muted-foreground">{run.assetSourceName ?? "—"}</td>
                          <td className="py-2 pr-3">
                            <StateBadge tone={status.tone}>{status.texto}</StateBadge>
                          </td>
                          <td className="py-2 pr-3 text-muted-foreground">
                            {run.successCount}/{run.requestedCount}
                            {run.failedCount > 0 ? ` (${run.failedCount} falhas)` : ""}
                          </td>
                          <td className="py-2 text-muted-foreground">
                            {new Date(run.createdAt).toLocaleString("pt-BR")}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </PanelContent>
        </Panel>
      </div>
    </AppShell>
  );
}
