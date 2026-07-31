import { AppShell } from "@/components/app-shell/app-shell";
import { JogosTable } from "@/components/catalogo/jogos-table";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { PageContainer } from "@/components/ui/page";
import { JOGOS_PAGE_SIZE, getJogos, getJogosPaged } from "@/lib/catalogo/queries";

/**
 * Lista de Jogos (`game`) — redesenhada em 2026-07-31 para o mesmo padrão
 * das telas Expansão/Card Set: cadastro e edição em Dialog (não mais
 * formulário/linha editável direto na página), busca e paginação
 * server-driven via URL (`?q=`/`?page=`, mesmo mecanismo de Expansões),
 * cabeçalho de tabela destacado e ações rápidas (editar/excluir) por
 * linha. Título da página acima dos cards de indicadores (`JogosStats`),
 * a partir de referência visual de Dashboard anexada por Fabrício.
 *
 * `getJogos()` (lista completa, sem paginação/filtro) segue alimentando só
 * os indicadores — eles representam o domínio inteiro, não a página/busca
 * atual da tabela. `getJogosPaged()` é a versão nova, usada pela tabela.
 *
 * Cadastro/edição continuam via `admin_create_game()`/`admin_update_game()`
 * (ADR-023) — nenhuma mudança de regra de negócio.
 */
export default async function JogosPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; page?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Jogos");
  if (denied) return denied;

  const { q, page: pageParam } = await searchParams;
  const query = q?.trim() ?? "";
  const requestedPage = Math.max(0, Number.parseInt(pageParam ?? "0", 10) || 0);

  const [jogos, firstAttempt] = await Promise.all([
    getJogos(supabase),
    getJogosPaged(supabase, {
      search: query || undefined,
      limit: JOGOS_PAGE_SIZE,
      offset: requestedPage * JOGOS_PAGE_SIZE,
    }),
  ]);

  // Página pedida na URL ficou fora do intervalo (ex.: usuário estava na
  // página 3 e a busca reduziu o resultado para 1 página) — busca de novo
  // já com a página válida, em vez de mostrar uma tabela vazia enganosa.
  let page = requestedPage;
  let paged = firstAttempt;
  const totalPages = Math.max(1, Math.ceil(firstAttempt.totalCount / JOGOS_PAGE_SIZE));
  if (requestedPage > 0 && requestedPage >= totalPages) {
    page = totalPages - 1;
    paged = await getJogosPaged(supabase, {
      search: query || undefined,
      limit: JOGOS_PAGE_SIZE,
      offset: page * JOGOS_PAGE_SIZE,
    });
  }

  return (
    <AppShell title="Jogos">
      <PageContainer>
        <JogosTable jogos={jogos} items={paged.items} totalCount={paged.totalCount} page={page} query={query} />
      </PageContainer>
    </AppShell>
  );
}
