import { AlertTriangle, ArrowRight, BookOpen, Layers } from "lucide-react";
import Link from "next/link";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioColecaoSeletor } from "@/components/catalogo/relatorio-colecao-seletor";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioPrintButton } from "@/components/catalogo/relatorio-print-button";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { Card, CardContent } from "@/components/ui/card";
import {
  DataTable,
  DataTableCell,
  DataTableHead,
  DataTableHeadCell,
  DataTableHeadRow,
  DataTableRow,
} from "@/components/ui/data-table";
import { EmptyState } from "@/components/ui/empty-state";
import { InlineFeedback } from "@/components/ui/feedback";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import {
  buildVariantSummaryModel,
  cartaVariantCount,
  hasCartaVariants,
  VARIANT_LABEL_SEPARATOR,
} from "@/lib/catalogo/carta-variant-summary";
import type { CartaCompletaRow, CartaSemPadraoRow } from "@/lib/catalogo/queries";
import {
  getCardSetByCode,
  getCardSetsForCartas,
  getCartasCompletas,
  getCartasSemVariantePadrao,
} from "@/lib/catalogo/queries";
import { cn, formatNumber } from "@/lib/utils";

const TITULO = "Card Variants por Carta";
const SUBTITULO = "Todas as Cards da Coleção, com as Card Variants já cadastradas para cada uma.";
const COLUNAS = 4;
const BASE_PATH = "/catalogo/relatorios/variantes-por-carta";

type VarianteFiltro = "todas" | "com" | "sem";

const TITULO_PENDENCIAS = "Cartas sem variante padrão";
const SUBTITULO_PENDENCIAS =
  "Cartas ativas, em todo o catálogo, com variações cadastradas e nenhuma definida como padrão.";

/**
 * "001/086" — mesma lógica de `formatCollectorTotal`/`cartaFullNumber` em
 * `cartas-gallery.tsx` e `card-set-cartas-grid.tsx`: duplicada localmente por
 * ser um helper pequeno de 1 linha (mesmo padrão já usado nos outros dois
 * lugares — nenhum dos dois foi extraído para um util compartilhado, então
 * não parti esta consistência sozinho).
 */
function formatCollectorNumber(carta: Pick<CartaCompletaRow, "collectorNumber" | "collectorTotal">): string {
  return carta.collectorTotal
    ? `${carta.collectorNumber}/${String(carta.collectorTotal).padStart(3, "0")}`
    : carta.collectorNumber;
}

/**
 * Lista de variantes de uma carta — uma linha por variante, na ordem da F1;
 * acabamento em tom principal, tiragem/Edition Context como qualificadores
 * (mesma leitura do popover da galeria). Extraída em P1 (2026-10-11) para a
 * tabela por Coleção e a de pendências usarem exatamente a mesma célula.
 */
function VariantesCadastradas({ view, cartaName }: { view: CartaCompletaRow["variantView"]; cartaName: string }) {
  const resumo = buildVariantSummaryModel(view, cartaName);
  if (resumo.kind === "HIDDEN") return <span className="italic text-neutral-400">Sem variante</span>;
  // D2: sem fallback para os nomes legados.
  if (resumo.kind === "UNAVAILABLE") return <span className="italic text-neutral-500">Detalhes indisponíveis</span>;
  return (
    <ul className="space-y-px">
      {resumo.lines.map((line) => (
        <li key={line.id}>
          {line.parts.map((part, i) => (
            <span key={part.axis} className={part.emphasis === "primary" ? "text-neutral-700" : "text-neutral-500"}>
              {i > 0 ? VARIANT_LABEL_SEPARATOR : null}
              {part.text}
            </span>
          ))}
          {line.repeatedLabel ? <span className="ml-1 text-[10px] italic text-neutral-400">(rótulo repetido)</span> : null}
          {line.isDefault ? <span className="ml-1 text-[10px] font-medium text-neutral-700">(padrão)</span> : null}
        </li>
      ))}
    </ul>
  );
}

/**
 * P1 (2026-10-11) — "Só cartas sem padrão": alterna o relatório entre a
 * visão por Coleção e a lista de pendências do catálogo inteiro. Link (não
 * estado de cliente), mesmo princípio de `RelatorioVariantesFiltro`.
 * Selecionar uma Coleção no seletor sai do modo (o link do seletor não leva
 * `pendencias`).
 */
function RelatorioPendenciasToggle({ ativo, cardSetCode }: { ativo: boolean; cardSetCode?: string }) {
  const href = ativo ? (cardSetCode ? `${BASE_PATH}?cardSet=${cardSetCode}` : BASE_PATH) : `${BASE_PATH}?pendencias=sem-padrao`;
  return (
    <Link
      href={href}
      aria-pressed={ativo}
      className={cn(
        "inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border px-3 py-1 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring print:hidden",
        ativo
          ? "border-primary/40 bg-primary/5 text-primary-ink"
          : "border-border text-muted-foreground hover:bg-surface-muted hover:text-foreground",
      )}
    >
      <AlertTriangle className="h-3 w-3" aria-hidden="true" />
      Só cartas sem padrão
    </Link>
  );
}

/**
 * Filtro "Variações" do relatório CV-03 (2026-08-15) — mesmas 3 opções e
 * mesma linguagem visual (chip `rounded-full`) do filtro equivalente de
 * `/catalogo/cartas` (`VarianteFilterGroup`, CV-02), mas URL-driven via
 * `<Link>` em vez de estado local — este módulo (Central de Relatórios) é
 * inteiramente server-rendered/imprimível, sem componente cliente próprio
 * além do seletor de Coleção (`RelatorioColecaoSeletor`) e do botão de
 * impressão; um filtro por link mantém a mesma consistência, sem introduzir
 * JS de cliente só para isto. `print:hidden` — a folha impressa já reflete o
 * filtro escolhido na própria tabela, o controle de troca não faz sentido
 * impresso.
 */
function RelatorioVariantesFiltro({ cardSetCode, ativo }: { cardSetCode: string; ativo: VarianteFiltro }) {
  const opcoes: { code: VarianteFiltro; label: string }[] = [
    { code: "todas", label: "Todas" },
    { code: "com", label: "Com variantes" },
    { code: "sem", label: "Sem variantes" },
  ];

  return (
    <div className="flex flex-wrap gap-1.5 print:hidden" role="group" aria-label="Filtrar por Variações">
      {opcoes.map((opcao) => {
        const active = ativo === opcao.code;
        const href =
          opcao.code === "todas"
            ? `${BASE_PATH}?cardSet=${cardSetCode}`
            : `${BASE_PATH}?cardSet=${cardSetCode}&variantes=${opcao.code}`;
        return (
          <Link
            key={opcao.code}
            href={href}
            aria-pressed={active}
            className={cn(
              "inline-flex shrink-0 items-center whitespace-nowrap rounded-full border px-3 py-1 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
              active
                ? "border-primary/40 bg-primary/5 text-primary-ink"
                : "border-border text-muted-foreground hover:bg-surface-muted hover:text-foreground",
            )}
          >
            {opcao.label}
          </Link>
        );
      })}
    </div>
  );
}

/**
 * Relatório "Card Variants por Carta" (CV-03, Central de Relatórios,
 * 2026-08-15) — administrador escolhe uma Coleção e vê todas as Cards dela
 * com as Card Variants já cadastradas (nome + quantidade), inclusive as
 * Cards sem nenhuma variante ainda. Somente leitura, admin-only (mesmo
 * `requireCatalogoAdmin` de todo o Catálogo Editorial) — nenhum CRUD de Card
 * Variant nesta tela, mesma fronteira de `ADR-028`. Escopo explicitamente
 * fora desta rodada: modelagem Vintage/Promo (ver backlog em `ROADMAP.md`).
 *
 * Mesmo padrão estrutural de "Checklist"/"Resumo" (os 2 outros relatórios
 * que mostram uma Coleção por vez): `RelatorioColecaoSeletor` para escolher
 * a Coleção via `?cardSet=`, `RelatorioFolha`/`RelatorioCabecalho`/
 * `RelatorioRodape`/`RelatorioPrintButton` — mesma "folha" A4 imprimível de
 * todo o módulo, sem tela paralela.
 *
 * Consulta: reaproveita `getCartasCompletas()` sem nenhuma alteração — desde
 * o CV-02 (mesmo dia), esta função já embute `card_variant(card_variant_type
 * (name, display_order))` no único `.select()` por Card Set, então
 * `carta.variantNames` (nomes já ordenados por `display_order`, não por
 * `variant_order` — ver `queries.ts`) chega pronta, sem view/RPC/migration
 * nova e sem round-trip por Card. Filtro "Variações" aplicado em memória
 * sobre o array já carregado (`cartasFiltradas`), mesmo princípio do filtro
 * client-side de `/catalogo/cartas` — a diferença aqui é que a filtragem
 * roda no servidor (parâmetro de URL), não no cliente, para não fugir do
 * padrão 100% server-rendered do resto deste módulo.
 *
 * F2.3 (VARIANT-DISPLAY-SEMANTICS-01, 2026-10-09): coluna, quantidade, filtro
 * e totais passaram a usar `carta.variantView` (F2.1) no lugar de
 * `variantNames`. Cada variante sai numa linha com a identidade completa
 * (acabamento / tiragem / Edition Context, D1); erro da F1 mostra "Detalhes
 * indisponíveis" (D2); quantidade = `rawCount` (G-COMP PASS). Ver
 * `docs/architecture/variant-display-semantics.md`.
 */
export default async function RelatorioVariantesPorCartaPage({
  searchParams,
}: {
  searchParams: Promise<{ cardSet?: string; variantes?: string; pendencias?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Catálogo editorial", BookOpen);
  if (denied) return denied;

  const { cardSet: cardSetCode, variantes, pendencias } = await searchParams;
  const filtro: VarianteFiltro = variantes === "com" || variantes === "sem" ? variantes : "todas";
  const modoPendencias = pendencias === "sem-padrao";

  if (modoPendencias) {
    const [cardSets, pendentes] = await Promise.all([
      getCardSetsForCartas(supabase),
      getCartasSemVariantePadrao(supabase),
    ]);
    return <RelatorioPendencias cardSets={cardSets} pendentes={pendentes} />;
  }

  const [cardSets, cardSet] = await Promise.all([
    getCardSetsForCartas(supabase),
    cardSetCode ? getCardSetByCode(supabase, cardSetCode) : Promise.resolve(null),
  ]);
  // Ativas apenas (comportamento padrão de `getCartasCompletas`, sem
  // `incluirInativas`) — mesmo critério já usado por "Checklist por
  // Coleção": um relatório administrativo de variantes não deveria listar
  // Cards desativadas junto com as vigentes.
  const cartas = cardSet ? await getCartasCompletas(supabase, cardSet.id) : [];

  // F2.3 (VARIANT-DISPLAY-SEMANTICS-01): presença e contagem vêm de
  // `variantView` (F2.1). `rawCount` = `count(card_variant)` por G-COMP PASS.
  // Carta com ERROR conta como "com variante" (há linhas, com dados
  // incompletos — D2), nunca como "sem".
  const cartasFiltradas = cartas.filter((carta) => {
    if (filtro === "com") return hasCartaVariants(carta.variantView);
    if (filtro === "sem") return !hasCartaVariants(carta.variantView);
    return true;
  });

  const totalSemVariante = cartas.filter((carta) => !hasCartaVariants(carta.variantView)).length;
  // Soma da coluna Quantidade — sobre `cartasFiltradas` (respeita o filtro
  // Todas/Com/Sem ativo), não sobre `cartas`: pedido de Fabrício foi a soma
  // da coluna tal como exibida na tabela, não um total fixo da Coleção.
  const contagensFiltradas = cartasFiltradas.map((carta) => cartaVariantCount(carta.variantView));
  const totalVariantesFiltradas = contagensFiltradas.reduce<number>((soma, n) => soma + (n ?? 0), 0);
  // Contagem desconhecida (ERROR sem lista) não pode ser somada como zero
  // silenciosamente: o total ganha "+" e uma nota abaixo da tabela.
  const totalIncompleto = contagensFiltradas.some((n) => n === null);

  return (
    <AppShell title="Catálogo editorial" icon={BookOpen}>
      <PageContainer width="wide">
        <PageHeader className="print:hidden">
          <PageHeading>
            <div className="flex items-center gap-2">
              <Layers className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>{TITULO}{cardSet ? ` — ${cardSet.code} · ${cardSet.name}` : ""}</PageTitle>
            </div>
            <PageDescription>{SUBTITULO}</PageDescription>
          </PageHeading>
          {cardSet && <RelatorioPrintButton />}
        </PageHeader>

        <div className="space-y-3 print:hidden">
          <div className="flex flex-wrap items-center gap-3">
            <RelatorioColecaoSeletor cardSets={cardSets} selectedCode={cardSetCode} basePath={BASE_PATH} />
            <RelatorioPendenciasToggle ativo={false} />
          </div>
          {cardSet && <RelatorioVariantesFiltro cardSetCode={cardSet.code} ativo={filtro} />}
        </div>

        {!cardSet ? (
          <Card density="compact">
            <CardContent density="compact" className="pt-4">
              <EmptyState
                title="Selecione uma Coleção"
                description="Escolha uma Coleção acima para ver as Card Variants cadastradas."
              />
            </CardContent>
          </Card>
        ) : (
          <RelatorioFolha>
            {cartasFiltradas.length === 0 ? (
              <>
                <RelatorioCabecalho
                  titulo={TITULO}
                  subtitulo={SUBTITULO}
                  identificacaoColecao={`${cardSet.code} · ${cardSet.name}`}
                  colecaoLogoUrl={cardSet.logoUrl}
                />
                <div className="px-6 print:px-0">
                  <EmptyState
                    title={cartas.length === 0 ? "Nenhuma Carta cadastrada nesta Coleção" : "Nenhuma Carta encontrada"}
                    description={cartas.length === 0 ? undefined : "Ajuste o filtro de Variações."}
                  />
                </div>
              </>
            ) : (
              // `<thead>` repete nativamente em toda página impressa quando a
              // tabela fragmenta em mais de uma folha — mesmo mecanismo já
              // usado em "Cobertura de Card Variant"/"Qualidade do Catálogo".
              <DataTable>
                <DataTableHead>
                  <tr>
                    <th colSpan={COLUNAS} className="p-0 text-left font-normal">
                      <RelatorioCabecalho
                        titulo={TITULO}
                        subtitulo={SUBTITULO}
                        identificacaoColecao={`${cardSet.code} · ${cardSet.name}`}
                        colecaoLogoUrl={cardSet.logoUrl}
                      />
                    </th>
                  </tr>
                  {/* Cor literal, não token — ver nota completa em
                      cobertura-geral/page.tsx (mesmo fix, 2026-08-23). */}
                  {/* Fundo em cada `th`, não na `tr` (2026-08-23, fix reportado
                      por Fabrício — só metade do cabeçalho ficava cinza na
                      impressão). Ver nota completa em cobertura-geral/page.tsx. */}
                  <DataTableHeadRow className="border-neutral-200 text-neutral-500">
                    <DataTableHeadCell className="bg-neutral-50 pl-6 print:pl-0">Número</DataTableHeadCell>
                    <DataTableHeadCell className="bg-neutral-50">Nome</DataTableHeadCell>
                    <DataTableHeadCell className="bg-neutral-50">Variantes cadastradas</DataTableHeadCell>
                    <DataTableHeadCell
                      align="center"
                      className="bg-neutral-50 pr-6 last:pr-6 print:pr-0 print:last:pr-0"
                    >
                      Quantidade
                    </DataTableHeadCell>
                  </DataTableHeadRow>
                </DataTableHead>
                <tbody>
                  {cartasFiltradas.map((carta, index) => {
                    // Cards sem variante ficam claramente identificadas pelo
                    // texto "Sem variante" (itálico, tom mais claro) em vez
                    // de uma célula vazia — sem depender só de cor, mesmo
                    // cuidado de acessibilidade/impressão P&B já aplicado à
                    // tag monocromática de `/catalogo/cartas` (CV-02).
                    const quantidade = cartaVariantCount(carta.variantView);
                    return (
                      <DataTableRow key={carta.id} className={cn(index % 2 === 1 && "bg-[#F7F5ED]")}>
                        <DataTableCell className="py-1.5 pl-6 text-xs tabular-nums text-neutral-500 print:pl-0">
                          {formatCollectorNumber(carta)}
                        </DataTableCell>
                        <DataTableCell className="py-1.5 text-xs text-neutral-900">{carta.name}</DataTableCell>
                        <DataTableCell className="py-1.5 text-xs text-neutral-500">
                          <VariantesCadastradas view={carta.variantView} cartaName={carta.name} />
                        </DataTableCell>
                        <DataTableCell
                          align="center"
                          className="py-1.5 pr-6 text-xs tabular-nums text-neutral-500 last:pr-6 print:pr-0 print:last:pr-0"
                        >
                          {quantidade ?? "—"}
                        </DataTableCell>
                      </DataTableRow>
                    );
                  })}
                  {/* Linha de total — soma da coluna Quantidade sobre as
                      Cards efetivamente exibidas (`cartasFiltradas`, respeita
                      o filtro Todas/Com/Sem ativo), mesmo padrão visual de
                      linha de total já usado em "Qualidade do
                      Catálogo"/"Cobertura de Card Variant" (borda superior
                      dupla, fundo destacado, negrito). */}
                  <tr className="border-t-2 border-neutral-400 bg-[#F0EEE3] font-semibold">
                    <DataTableCell className="py-1.5 pl-6 text-xs text-neutral-900 print:pl-0" colSpan={3}>
                      Total
                    </DataTableCell>
                    <DataTableCell
                      align="center"
                      className="py-1.5 pr-6 text-xs tabular-nums text-neutral-900 last:pr-6 print:pr-0 print:last:pr-0"
                    >
                      {formatNumber(totalVariantesFiltradas)}
                      {totalIncompleto ? "+" : ""}
                    </DataTableCell>
                  </tr>
                </tbody>
              </DataTable>
            )}

            {cartas.length > 0 && (
              <p className="px-6 pb-4 text-xs text-muted-foreground print:px-0">
                {formatNumber(totalSemVariante)} de {formatNumber(cartas.length)} Cards desta Coleção ainda sem
                nenhuma Card Variant cadastrada.
                {totalIncompleto
                  ? " O total marcado com “+” exclui Cards cuja quantidade não pôde ser lida (Detalhes indisponíveis)."
                  : ""}
              </p>
            )}

            <RelatorioRodape />
          </RelatorioFolha>
        )}
      </PageContainer>
    </AppShell>
  );
}

/**
 * P1 (2026-10-11) — modo "Só cartas sem padrão": pendências do catálogo
 * inteiro (view `catalog_card_variant_default_pending`, Query 2266), na mesma
 * folha imprimível do relatório. Cada linha leva à galeria da Coleção já
 * filtrada em "Sem padrão" (`?variacoes=sem-padrao`), onde o padrão é
 * definido; ao voltar aqui a carta resolvida já não aparece (página dinâmica).
 */
function RelatorioPendencias({
  cardSets,
  pendentes,
}: {
  cardSets: Awaited<ReturnType<typeof getCardSetsForCartas>>;
  pendentes: { rows: CartaSemPadraoRow[]; error: string | null; truncated: boolean };
}) {
  const { rows, error, truncated } = pendentes;
  const colecoes = new Set(rows.map((row) => row.cardSetCode)).size;
  const identificacao =
    rows.length === 0
      ? "Todo o catálogo"
      : `Todo o catálogo · ${formatNumber(rows.length)} ${rows.length === 1 ? "carta" : "cartas"} em ${formatNumber(colecoes)} ${colecoes === 1 ? "Coleção" : "Coleções"}`;

  return (
    <AppShell title="Catálogo editorial" icon={BookOpen}>
      <PageContainer width="wide">
        <PageHeader className="print:hidden">
          <PageHeading>
            <div className="flex items-center gap-2">
              <Layers className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>
                {TITULO_PENDENCIAS}
                {error ? "" : ` (${formatNumber(rows.length)})`}
              </PageTitle>
            </div>
            <PageDescription>{SUBTITULO_PENDENCIAS}</PageDescription>
          </PageHeading>
          {!error && rows.length > 0 && <RelatorioPrintButton />}
        </PageHeader>

        <div className="flex flex-wrap items-center gap-3 print:hidden">
          <RelatorioColecaoSeletor cardSets={cardSets} basePath={BASE_PATH} />
          <RelatorioPendenciasToggle ativo />
        </div>

        {error ? (
          <div role="alert">
            <InlineFeedback tone="error">Não foi possível carregar as pendências ({error}).</InlineFeedback>
          </div>
        ) : (
          <RelatorioFolha>
            {rows.length === 0 ? (
              <>
                <RelatorioCabecalho titulo={TITULO_PENDENCIAS} subtitulo={SUBTITULO_PENDENCIAS} identificacaoColecao={identificacao} />
                <div className="px-6 print:px-0">
                  <EmptyState
                    title="Nenhuma carta sem variante padrão"
                    description="Todas as cartas ativas com variações já têm um padrão definido."
                  />
                </div>
              </>
            ) : (
              <DataTable>
                <DataTableHead>
                  <tr>
                    <th colSpan={5} className="p-0 text-left font-normal">
                      <RelatorioCabecalho titulo={TITULO_PENDENCIAS} subtitulo={SUBTITULO_PENDENCIAS} identificacaoColecao={identificacao} />
                    </th>
                  </tr>
                  <DataTableHeadRow className="border-neutral-200 text-neutral-500">
                    <DataTableHeadCell className="bg-neutral-50 pl-6 print:pl-0">Coleção</DataTableHeadCell>
                    <DataTableHeadCell className="bg-neutral-50">Número</DataTableHeadCell>
                    <DataTableHeadCell className="bg-neutral-50">Nome</DataTableHeadCell>
                    <DataTableHeadCell className="bg-neutral-50">Variantes cadastradas</DataTableHeadCell>
                    <DataTableHeadCell className="bg-neutral-50 pr-6 last:pr-6 print:hidden">
                      <span className="sr-only">Ação</span>
                    </DataTableHeadCell>
                  </DataTableHeadRow>
                </DataTableHead>
                <tbody>
                  {rows.map((row, index) => (
                    <DataTableRow key={row.id} className={cn(index % 2 === 1 && "bg-[#F7F5ED]")}>
                      <DataTableCell className="py-1.5 pl-6 align-top text-xs text-neutral-700 print:pl-0">
                        <span className="font-medium text-neutral-900">{row.cardSetCode}</span>
                        <span className="block text-[10px] text-neutral-500">{row.cardSetName}</span>
                      </DataTableCell>
                      <DataTableCell className="py-1.5 align-top text-xs tabular-nums text-neutral-500">
                        {formatCollectorNumber(row)}
                      </DataTableCell>
                      <DataTableCell className="py-1.5 align-top text-xs text-neutral-900">{row.name}</DataTableCell>
                      <DataTableCell className="py-1.5 align-top text-xs text-neutral-500">
                        <VariantesCadastradas view={row.variantView} cartaName={row.name} />
                      </DataTableCell>
                      <DataTableCell className="py-1.5 pr-6 align-top text-right last:pr-6 print:hidden">
                        <Link
                          href={`/catalogo/cartas?set=${encodeURIComponent(row.cardSetCode)}&variacoes=sem-padrao`}
                          aria-label={`Definir variante padrão de ${row.name}, ${row.cardSetCode} ${row.collectorNumber}`}
                          className="inline-flex min-h-8 items-center gap-1 whitespace-nowrap rounded-md px-2 text-xs font-medium text-primary-ink underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                          Definir padrão
                          <ArrowRight className="h-3 w-3" aria-hidden="true" />
                        </Link>
                      </DataTableCell>
                    </DataTableRow>
                  ))}
                </tbody>
              </DataTable>
            )}

            {truncated && (
              <p className="px-6 pb-4 text-xs text-muted-foreground print:px-0">
                Mostrando as primeiras {formatNumber(rows.length)} pendências; resolva estas para ver as demais.
              </p>
            )}

            <RelatorioRodape />
          </RelatorioFolha>
        )}
      </PageContainer>
    </AppShell>
  );
}
