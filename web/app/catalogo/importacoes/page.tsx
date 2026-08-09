import { History } from "lucide-react";
import Link from "next/link";
import { AppShell } from "@/components/app-shell/app-shell";
import { ImportacoesTable } from "@/components/catalogo/importacoes-table";
import { ImportacoesTendencia } from "@/components/catalogo/importacoes-tendencia";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { getCatalogImportJobIdsExigindoAtencao, getImportacoes } from "@/lib/catalogo/queries";

/**
 * Histórico completo de execuções de importação — versão sem `limit` do
 * bloco "Atividade recente" da Visão Geral, por ser o destino dedicado desta
 * informação.
 *
 * Ampliado em 2026-08-08 (Sprint Gerencial 1) para unificar as duas frentes
 * de importação do Catálogo: já trazia só `asset_import_run` (pipeline de
 * Imagens); `getImportacoes` passou a unir também `catalog_import_job`
 * (pipeline de Cartas), mesma lógica de fusão por data já usada em
 * `getAtividadeRecente`.
 *
 * Revisão de UX/layout (2026-08-09): a tabela em si (`<table>` simples,
 * colunas Execução/Pipeline/Tipo/Card Set/Fonte/Status/Resultado/Data, sem
 * busca) foi substituída por `ImportacoesTable`
 * (`components/catalogo/importacoes-table.tsx`), que adota o mesmo modelo já
 * aprovado do bloco "Atividade Recente" da Visão Geral — busca no topo,
 * filtro de chips por Pipeline, colunas Data | Coleção | Execução | Operação
 * | Resultado | Status (nesta ordem, "Coleção" em vez de "Card Set"),
 * paginação. "Tipo"/"Fonte" deixaram de ser colunas — não faziam parte do
 * modelo aprovado; a distinção de pipeline continua visível em "Operação" e
 * agora também no filtro de chips. Os dois filtros de URL abaixo
 * (`?atencao=1`, `?cardSet=`) continuam resolvidos aqui, no servidor, antes
 * da lista chegar ao componente — inalterados nesta rodada.
 *
 * `?atencao=1` (2026-08-08, mesma Sprint): destino do drill-down do StatCard
 * "Pendências" da Visão Geral. `importacoesAguardandoRevisaoOuErro` conta
 * SÓ `catalog_import_job` (pipeline CARTAS) — `getImportacoesAguardandoRevisaoOuErro()`
 * nunca leu `asset_import_run`.
 *
 * Corrigido em 2026-08-08 (revisão de semântica, mesma Sprint): o filtro
 * não checa mais status isoladamente — reutiliza
 * `getCatalogImportJobIdsExigindoAtencao()` (`queries.ts`), a mesma fonte
 * lógica do StatCard "Pendências". Checar só o texto do status vazaria
 * linhas de IMAGENS com o mesmo status de `catalog_import_job` (bug real já
 * corrigido antes) e, sem a regra de "job mais recente por Coleção", também
 * contaria jobs antigos já superados por uma tentativa posterior resolvida
 * — achado real validado contra produção pela Query 2822 antes desta
 * implementação (os 9 jobs que a métrica antiga contava eram todos
 * tentativas anteriores a um job `COMPLETED` mais recente da mesma
 * Coleção). Filtro aplicado em memória sobre o histórico completo já
 * buscado (`ids.has(run.id)` — `run.id` de uma linha CARTAS É o
 * `catalog_import_job.id`, ver `getImportacoes()`), com um link "Limpar
 * filtro" para voltar à lista inteira.
 *
 * `?cardSet=<code>` (2026-08-08, mesmo dia — ação contextual "Histórico de
 * Importações" do hub de Card Set, `/catalogo/card-sets/{code}`) — mesmo
 * princípio de `?atencao=1`: filtro em memória sobre `getImportacoes()`,
 * sem query/view nova (cada linha já traz `cardSetCode`). Usa o `code`, não
 * o `id` — é o que o hub já tem na própria rota, sem consulta extra para
 * resolver. Combinável com `?atencao=1` (aplicados em série); nenhum dos
 * dois exclui o outro.
 */
export default async function ImportacoesPage({
  searchParams,
}: {
  searchParams: Promise<{ atencao?: string; cardSet?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Histórico de importações", History);
  if (denied) return denied;

  const { atencao, cardSet } = await searchParams;
  const filtroAtencao = atencao === "1";
  const filtroCardSet = cardSet?.trim() || null;

  const [todasImportacoes, idsExigindoAtencao] = await Promise.all([
    getImportacoes(supabase),
    filtroAtencao ? getCatalogImportJobIdsExigindoAtencao(supabase) : Promise.resolve(null),
  ]);
  let importacoes =
    filtroAtencao && idsExigindoAtencao
      ? todasImportacoes.filter((run) => run.pipeline === "CARTAS" && idsExigindoAtencao.has(run.id))
      : todasImportacoes;
  if (filtroCardSet) {
    importacoes = importacoes.filter((run) => run.cardSetCode === filtroCardSet);
  }

  const filtrosAtivos = [
    filtroAtencao ? "aguardando revisão ou erro" : null,
    filtroCardSet ? `Coleção ${filtroCardSet}` : null,
  ].filter(Boolean);

  return (
    <AppShell title="Histórico de importações" icon={History}>
      <div className="mx-auto max-w-6xl space-y-4">
        <div className="flex items-center gap-2">
          <History className="h-5 w-5 shrink-0 text-muted-foreground" aria-hidden="true" />
          <h1 className="font-heading text-xl font-medium text-foreground">Histórico de importações</h1>
        </div>

        <ImportacoesTendencia importacoes={importacoes} />

        {filtrosAtivos.length > 0 && (
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <span>Filtrando por: {filtrosAtivos.join(" · ")}</span>
            <Link href="/catalogo/importacoes" className="text-primary hover:underline">
              Limpar filtro
            </Link>
          </div>
        )}

        <ImportacoesTable importacoes={importacoes} />
      </div>
    </AppShell>
  );
}
