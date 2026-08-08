import { History } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { StateBadge } from "@/components/catalogo/state-badge";
import type { StateTone } from "@/components/catalogo/state-badge";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { getImportacoes } from "@/lib/catalogo/queries";
import type { ImportacaoPipeline } from "@/lib/catalogo/queries";

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

/** Rótulo do pipeline de origem — "Cartas" (catalog_import_job) ou "Imagens" (asset_import_run). */
const PIPELINE_LABEL: Record<ImportacaoPipeline, string> = {
  CARTAS: "Cartas",
  IMAGENS: "Imagens",
};

/**
 * Histórico completo de execuções de importação — versão sem `limit` do
 * bloco "Atividade recente" da Visão Geral, com mais colunas (tipo, fonte,
 * idioma) por ser o destino dedicado desta informação.
 *
 * Ampliado em 2026-08-08 (Sprint Gerencial 1) para unificar as duas frentes
 * de importação do Catálogo: já trazia só `asset_import_run` (pipeline de
 * Imagens); `getImportacoes` passou a unir também `catalog_import_job`
 * (pipeline de Cartas), mesma lógica de fusão por data já usada em
 * `getAtividadeRecente`. Nova coluna "Pipeline" distingue a origem de cada
 * linha, já que "Tipo" (`runType`) só existe para o pipeline de Imagens —
 * fica "—" para linhas de Cartas (`getImportacoes` retorna `runType: null`
 * para `catalog_import_job`, que não tem esse conceito).
 */
export default async function ImportacoesPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Histórico de importações", History);
  if (denied) return denied;

  const importacoes = await getImportacoes(supabase);

  return (
    <AppShell title="Histórico de importações" icon={History}>
      <div className="mx-auto max-w-6xl space-y-4">
        <div className="flex items-center gap-2">
          <History className="h-5 w-5 shrink-0 text-muted-foreground" aria-hidden="true" />
          <h1 className="font-heading text-xl font-medium text-foreground">Histórico de importações</h1>
        </div>

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
                      <th className="py-1.5 pr-3 font-normal">Pipeline</th>
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
                          <td className="py-2 pr-3 text-muted-foreground">{PIPELINE_LABEL[run.pipeline]}</td>
                          <td className="py-2 pr-3 text-muted-foreground">
                            {run.runType ? (RUN_TYPE_LABEL[run.runType] ?? run.runType) : "—"}
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
