import { ScrollText } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { LogAtualizacoesResumo } from "@/components/catalogo/log-atualizacoes-resumo";
import { LogAtualizacoesTable } from "@/components/catalogo/log-atualizacoes-table";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import {
  LOG_ATUALIZACOES_PAGE_SIZE,
  getAdminUserOptions,
  getLogAtualizacoes,
  getLogAtualizacoesResumoSemanal,
} from "@/lib/catalogo/queries";

/**
 * Log de Atualizações — trilha de auditoria de escrita administrativa do
 * Catálogo Editorial (catalog_admin_action_log, ADR-023). V1 implementada
 * em 2026-08-09 (substitui o ComingSoonPage do bloco "Gerencial", ver
 * nav-config.ts), a partir de proposta técnica revisada e aprovada por
 * Fabrício: 3 gráficos semanais no topo (Cadastro/Alteração/Exclusão,
 * janela fixa de 12 semanas), tabela paginada/filtrada inteiramente
 * server-side (admin_list_catalog_action_log()) — primeira tela do módulo
 * nesse padrão, diferente do fetch-tudo-e-filtra-em-memória usado por
 * Importações/Atividade Recente/Cartas — e Dialog de Detalhes a partir do
 * metadata já resolvido no backend, sem diff antes/depois inventado.
 *
 * Mesmo mecanismo de "página pedida na URL ficou fora do intervalo" de
 * JogosPage — evita mostrar uma tabela vazia enganosa quando um filtro
 * reduz o total abaixo da página atualmente aberta.
 *
 * Ícone do título ausente, corrigido em 2026-08-09 (achado real de Fabrício
 * em inspeção geral das páginas do Catálogo Editorial) — o `PageTitle` desta
 * tela nunca tinha ganhado o wrapper `<div className="flex items-center
 * gap-2">` + ícone que todas as outras páginas do módulo usam (`ScrollText`,
 * o mesmo já passado para `AppShell`/nav).
 */
export default async function LogAtualizacoesPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; entidade?: string; acao?: string; usuario?: string; page?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Log de Atualizações", ScrollText);
  if (denied) return denied;

  const { q, entidade, acao, usuario, page: pageParam } = await searchParams;
  const search = q?.trim() ?? "";
  const entityType = entidade ?? "";
  const action = acao ?? "";
  const actorId = usuario ?? "";
  const requestedPage = Math.max(0, Number.parseInt(pageParam ?? "0", 10) || 0);

  const filtros = {
    search: search || undefined,
    entityType: entityType || undefined,
    action: action || undefined,
    actorId: actorId || undefined,
  };

  const [resumo, usuarios, firstAttempt] = await Promise.all([
    getLogAtualizacoesResumoSemanal(supabase),
    getAdminUserOptions(supabase),
    getLogAtualizacoes(supabase, {
      ...filtros,
      limit: LOG_ATUALIZACOES_PAGE_SIZE,
      offset: requestedPage * LOG_ATUALIZACOES_PAGE_SIZE,
    }),
  ]);

  let page = requestedPage;
  let paged = firstAttempt;
  const totalPages = Math.max(1, Math.ceil(firstAttempt.totalCount / LOG_ATUALIZACOES_PAGE_SIZE));
  if (requestedPage > 0 && requestedPage >= totalPages) {
    page = totalPages - 1;
    paged = await getLogAtualizacoes(supabase, {
      ...filtros,
      limit: LOG_ATUALIZACOES_PAGE_SIZE,
      offset: page * LOG_ATUALIZACOES_PAGE_SIZE,
    });
  }

  return (
    <AppShell title="Log de Atualizações" icon={ScrollText}>
      <PageContainer className="space-y-4">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <ScrollText className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Log de Atualizações</PageTitle>
            </div>
            <PageDescription>Trilha de auditoria das escritas administrativas do catálogo editorial.</PageDescription>
          </PageHeading>
        </PageHeader>

        <LogAtualizacoesResumo resumo={resumo} />

        <LogAtualizacoesTable
          items={paged.items}
          totalCount={paged.totalCount}
          page={page}
          search={search}
          entityType={entityType}
          action={action}
          actorId={actorId}
          usuarios={usuarios}
        />
      </PageContainer>
    </AppShell>
  );
}
