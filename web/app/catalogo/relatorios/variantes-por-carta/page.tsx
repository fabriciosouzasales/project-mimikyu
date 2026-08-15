import { BookOpen, Layers } from "lucide-react";
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
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import type { CartaCompletaRow } from "@/lib/catalogo/queries";
import { getCardSetByCode, getCardSetsForCartas, getCartasCompletas } from "@/lib/catalogo/queries";
import { cn, formatNumber } from "@/lib/utils";

const TITULO = "Card Variants por Carta";
const SUBTITULO = "Todas as Cards da Coleção, com as Card Variants já cadastradas para cada uma.";
const COLUNAS = 4;
const BASE_PATH = "/catalogo/relatorios/variantes-por-carta";

type VarianteFiltro = "todas" | "com" | "sem";

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
                ? "border-primary/40 bg-primary/5 text-primary"
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
 */
export default async function RelatorioVariantesPorCartaPage({
  searchParams,
}: {
  searchParams: Promise<{ cardSet?: string; variantes?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Catálogo editorial", BookOpen);
  if (denied) return denied;

  const { cardSet: cardSetCode, variantes } = await searchParams;
  const filtro: VarianteFiltro = variantes === "com" || variantes === "sem" ? variantes : "todas";

  const [cardSets, cardSet] = await Promise.all([
    getCardSetsForCartas(supabase),
    cardSetCode ? getCardSetByCode(supabase, cardSetCode) : Promise.resolve(null),
  ]);
  // Ativas apenas (comportamento padrão de `getCartasCompletas`, sem
  // `incluirInativas`) — mesmo critério já usado por "Checklist por
  // Coleção": um relatório administrativo de variantes não deveria listar
  // Cards desativadas junto com as vigentes.
  const cartas = cardSet ? await getCartasCompletas(supabase, cardSet.id) : [];

  const cartasFiltradas = cartas.filter((carta) => {
    if (filtro === "com") return carta.variantNames.length > 0;
    if (filtro === "sem") return carta.variantNames.length === 0;
    return true;
  });

  const totalSemVariante = cartas.filter((carta) => carta.variantNames.length === 0).length;
  // Soma da coluna Quantidade — sobre `cartasFiltradas` (respeita o filtro
  // Todas/Com/Sem ativo), não sobre `cartas`: pedido de Fabrício foi a soma
  // da coluna tal como exibida na tabela, não um total fixo da Coleção.
  const totalVariantesFiltradas = cartasFiltradas.reduce((soma, carta) => soma + carta.variantNames.length, 0);

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
          <RelatorioColecaoSeletor cardSets={cardSets} selectedCode={cardSetCode} basePath={BASE_PATH} />
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
                  <DataTableHeadRow className="bg-surface-muted">
                    <DataTableHeadCell className="pl-6 print:pl-0">Número</DataTableHeadCell>
                    <DataTableHeadCell>Nome</DataTableHeadCell>
                    <DataTableHeadCell>Variantes cadastradas</DataTableHeadCell>
                    <DataTableHeadCell align="center" className="pr-6 last:pr-6 print:pr-0 print:last:pr-0">
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
                    const semVariante = carta.variantNames.length === 0;
                    return (
                      <DataTableRow key={carta.id} className={cn(index % 2 === 1 && "bg-[#F7F5ED]")}>
                        <DataTableCell className="py-1.5 pl-6 text-xs tabular-nums text-neutral-500 print:pl-0">
                          {formatCollectorNumber(carta)}
                        </DataTableCell>
                        <DataTableCell className="py-1.5 text-xs text-neutral-900">{carta.name}</DataTableCell>
                        <DataTableCell className="py-1.5 text-xs text-neutral-500">
                          {semVariante ? <span className="italic text-neutral-400">Sem variante</span> : carta.variantNames.join(", ")}
                        </DataTableCell>
                        <DataTableCell
                          align="center"
                          className="py-1.5 pr-6 text-xs tabular-nums text-neutral-500 last:pr-6 print:pr-0 print:last:pr-0"
                        >
                          {carta.variantNames.length}
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
                    </DataTableCell>
                  </tr>
                </tbody>
              </DataTable>
            )}

            {cartas.length > 0 && (
              <p className="px-6 pb-4 text-xs text-muted-foreground print:px-0">
                {formatNumber(totalSemVariante)} de {formatNumber(cartas.length)} Cards desta Coleção ainda sem
                nenhuma Card Variant cadastrada.
              </p>
            )}

            <RelatorioRodape />
          </RelatorioFolha>
        )}
      </PageContainer>
    </AppShell>
  );
}
