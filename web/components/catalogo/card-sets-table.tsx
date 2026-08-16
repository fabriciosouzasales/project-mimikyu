"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { AlertTriangle, ChevronLeft, ChevronRight, Search } from "lucide-react";
import { useMemo, useState } from "react";
import { SetTypeTag } from "@/components/catalogo/set-type-tag";
import { StateBadge } from "@/components/catalogo/state-badge";
import { Button } from "@/components/ui/button";
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
import { Input } from "@/components/ui/input";
import { formatarData } from "@/lib/format-date";
import type { CardSetOverviewRow } from "@/lib/catalogo/queries";
import { formatNumber } from "@/lib/utils";

/**
 * Tabela de Card Sets da Visão Geral — migrada para o padrão introduzido em
 * Jogos (2026-07-31, aprovado por Fabrício): `Card` (não mais `Panel`) com
 * busca integrada no topo, cabeçalho destacado (`bg-surface-muted`) e
 * conteúdo rente às bordas do card. `Panel`/`PanelHeader` que envolviam esta
 * tabela saem de `page.tsx` — o próprio `Card` agora é a superfície.
 *
 * Diferença deliberada frente a Jogos: sem coluna "Ações" — o chevron por
 * linha já é o afordance de navegação (esta tabela é só leitura, cadastro/
 * edição de Card Set continua em /catalogo/card-sets).
 *
 * Paginação (2026-07-31, pedido de Fabrício: "no mesmo padrão que usamos na
 * tabela de Jogos") — mesmo footer visual (Mostrando X–Y de Z + setas
 * ícone + página atual/total), mas paginando em memória sobre a lista já
 * filtrada, não via `?page=`/nova consulta ao servidor: `getCardSetsOverview`
 * já traz todos os Card Sets de uma vez (a agregação por trás — cobertura
 * de imagens/cartas catalogadas — varre a tabela `card` inteira de qualquer
 * forma, então uma página por vez no servidor não economizaria a parte cara
 * da consulta). Página volta para a primeira sempre que a busca muda.
 *
 * Coluna "Jogo / Expansão" (2026-07-31, `/impeccable layout`, pedido de
 * Fabrício: "senti falta das informações do Jogo e expansão... cuidado com
 * o layout, não vai deixar a tabela com aparência de planilha") — em vez de
 * duas colunas novas de texto plano (que competiriam com Card Set/Tipo e
 * empurrariam a tabela para uma grade de dados crua), reaproveita o mesmo
 * idioma de duas linhas já usado na própria coluna Card Set: Expansão em
 * destaque (mais específica, o nível que importa para quem está lendo a
 * lista) e Jogo como legenda menor abaixo (categoria mais ampla, hoje quase
 * sempre repetida — só ganha relevância quando existir mais de um Jogo).
 * Busca local passa a casar também por esses dois campos.
 *
 * Ajuste (2026-07-31, pedido de Fabrício: cor fora do padrão e sem
 * centralizar) — Expansão trocou de `text-foreground` para
 * `text-muted-foreground`: essa coluna é dado de apoio (mesmo papel de
 * Tipo/Cartas/Imagens/Logo, todas em muted), não a identidade clicável da
 * linha (só o nome do Card Set, em `text-primary`, é link). Célula também
 * ganhou `align="center"` + `items-center`, alinhada ao cabeçalho — a
 * âncora à esquerda fica reservada à coluna Card Set (identidade da linha).
 *
 * Três ajustes pedidos por Fabrício (2026-08-08):
 *
 * 1. A coluna "Logo" deixou de ser um indicador textual (Cadastrada/—) e
 *    virou a primeira coluna da tabela, mostrando a imagem de fato (URL
 *    assinada de `getCardSetLogoUrls()`, já usada pela galeria de Card Sets
 *    — mesmo padrão de fallback: iniciais do nome quando não há logo, nunca
 *    ícone genérico). `CardSetOverviewRow.temLogo` (booleano) foi substituído
 *    por `logoUrl` em `web/lib/catalogo/queries.ts`.
 * 2. Ordenação passou de `release_order` ascendente (por Expansão) para
 *    `release_date` descendente, com `release_order` descendente como
 *    desempate — mesma dupla chave já usada por `sortCatalogoCardSets()`
 *    (`/catalogo/card-sets`, caminho sem filtro). A ordenação acontece no
 *    servidor (`sortCardSetsOverview()`, `queries.ts`) — este componente só
 *    filtra/pagina em memória sobre o array já ordenado, nunca reordena.
 * 3. "Jogo / Expansão" passou a mostrar o código da Expansão antes do nome
 *    (`"ME - Mega Evolution"`, não só `"Mega Evolution"`) — Jogo continua
 *    como legenda menor abaixo, inalterado.
 *
 * Ajuste seguinte, mesmo dia (Fabrício, revisão visual do resultado acima):
 * a caixa da logo tinha borda + fundo cinza (`border border-border
 * bg-surface-muted`) — removida, a imagem (ou as iniciais de fallback)
 * aparece direto, fundo transparente. Para caber uma logo maior sem
 * engordar a linha, o padding vertical da célula caiu de `py-2` (padrão de
 * `DataTableCell`) para `py-1.5`, e a caixa cresceu de `h-9 w-14` para
 * `h-12 w-20`. Nova coluna "Lançamento" (`release_date`, mesmo formato de
 * `formatarData()` já usado em Expansões/Jogos) acrescentada ao final,
 * antes do chevron de navegação.
 *
 * Últimos ajustes, rodada seguinte (Fabrício):
 *
 * 1. "Cartas" deixou de mostrar só `totalSetSize` (tamanho esperado do Set)
 *    e passou a mostrar `cardsCatalogados` DE `totalSetSize` — mesma lógica
 *    de "atual de esperado" já usada em "Imagens" (item 2).
 * 2. "Imagens" deixou de ser um badge binário (Completas/Pendente) e passou
 *    a mostrar a contagem real — `cardsComImagem` DE `cardsCatalogados`
 *    (novo campo em `CardSetOverviewRow`, já calculado por
 *    `getCardSetsOverview()`, só não estava exposto). "Esperado" aqui é
 *    `cardsCatalogados`, não `totalSetSize` — só cards já cadastradas podem
 *    ter imagem, então comparar contra o tamanho total do Set inflaria a
 *    pendência com cards que a Frente E ainda nem trouxe. Tom do badge
 *    (`StateBadge`) preservado: verde discreto quando completo, amarelo com
 *    `AlertTriangle` quando pendente — `muted` no caso-limite de 0 cards
 *    cadastradas (nada para cobrir ainda, não é uma pendência real).
 * 3. Linha inteira agora navega para o detalhe da Coleção — `onClick` +
 *    `cursor-pointer` em `DataTableRow`, via `useRouter().push()`. O link
 *    semântico/acessível por teclado continua sendo o nome da Coleção
 *    (`<Link>`, com `stopPropagation` para não disparar dois `push()`
 *    idênticos ao clicar nele); logo e chevron deixaram de ser `<Link>`
 *    próprios (navegação duplicada e redundante agora que a linha toda
 *    responde), viraram apresentação pura.
 *
 * Ajuste seguinte (Fabrício: "reduzir a altura das linhas para o limite") —
 * todas as células passaram de `py-2` (padrão de `DataTableCell`) ou `py-1.5`
 * (logo) para `py-1`, o mínimo que ainda respira um pouco em vez de colar no
 * texto. A partir daqui, quem governa a altura da linha é a caixa da logo
 * (`h-12`, 48px) — reduzir mais exigiria encolher a própria logo, não só o
 * padding da célula, e a logo maior foi um pedido explícito anterior.
 */
const CARD_SETS_PAGE_SIZE = 10;

/** Iniciais do nome da Coleção — mesmo fallback já usado por `CardSetGalleryCard` quando não há logo cadastrada. */
function getInitials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0]?.toUpperCase() ?? "")
    .join("");
}

/**
 * Nome da Coleção em `text-foreground` com `hover:text-primary-ink`
 * (2026-08-16, promovido de prova cromática isolada "onyx-preview" para
 * baseline — ver `app/globals.css`) — os nomes das coleções não precisam
 * ser todos dourados; dourado fica reservado para interação/estado
 * (instrução explícita, mantida ao promover a prova a padrão permanente).
 * `text-primary-ink` (não `text-primary` puro) por legibilidade — ver
 * `app/globals.css` para a distinção entre os dois tokens.
 */
export function CardSetsTable({ cardSets }: { cardSets: CardSetOverviewRow[] }) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(0);

  const filtrados = useMemo(() => {
    const termo = query.trim().toLowerCase();
    if (!termo) return cardSets;
    return cardSets.filter((set) =>
      [set.name, set.code, set.expansionCode, set.expansionName, set.gameName]
        .filter(Boolean)
        .some((campo) => campo!.toLowerCase().includes(termo)),
    );
  }, [cardSets, query]);

  const totalCount = filtrados.length;
  const totalPages = Math.max(1, Math.ceil(totalCount / CARD_SETS_PAGE_SIZE));
  const paginaAtual = Math.min(page, totalPages - 1);
  const itensPagina = filtrados.slice(
    paginaAtual * CARD_SETS_PAGE_SIZE,
    paginaAtual * CARD_SETS_PAGE_SIZE + CARD_SETS_PAGE_SIZE,
  );

  return (
    <Card density="compact" className="overflow-hidden">
      <div className="border-b border-border p-4">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setPage(0);
            }}
            placeholder="Buscar por Coleção, Jogo ou Expansão…"
            className="h-9 bg-surface-muted pl-9 text-xs"
            aria-label="Buscar Coleção"
          />
        </div>
      </div>

      <CardContent density="compact" className="px-0 pb-0">
        {cardSets.length === 0 ? (
          <EmptyState
            title="Nenhuma Coleção catalogada ainda"
            description="As Coleções aparecem aqui assim que forem cadastradas."
          />
        ) : filtrados.length === 0 ? (
          <EmptyState title={`Nenhum resultado para "${query}"`} description="Tente outro nome ou código." />
        ) : (
          <DataTable>
            <DataTableHead>
              <DataTableHeadRow className="bg-surface-muted">
                <DataTableHeadCell align="center" className="pl-4">
                  Logo
                </DataTableHeadCell>
                <DataTableHeadCell align="center">Coleção</DataTableHeadCell>
                <DataTableHeadCell align="center">Jogo / Expansão</DataTableHeadCell>
                <DataTableHeadCell align="center">Tipo</DataTableHeadCell>
                <DataTableHeadCell align="center">Cartas</DataTableHeadCell>
                <DataTableHeadCell align="center">Imagens</DataTableHeadCell>
                <DataTableHeadCell align="center">Lançamento</DataTableHeadCell>
                <DataTableHeadCell align="center" className="pr-4 last:pr-4" />
              </DataTableHeadRow>
            </DataTableHead>
            <tbody>
              {itensPagina.map((set) => {
                const semCartas = set.cardsCatalogados === 0;
                const imagensCompletas = !semCartas && set.cardsComImagem === set.cardsCatalogados;
                const imagensTone = semCartas ? "muted" : imagensCompletas ? "success" : "warning";

                return (
                  <DataTableRow
                    key={set.code}
                    className="cursor-pointer"
                    onClick={() => router.push(`/catalogo/card-sets/${set.code}`)}
                  >
                    <DataTableCell align="center" className="py-1 pl-4">
                      <div className="inline-flex h-12 w-20 items-center justify-center">
                        {set.logoUrl ? (
                          // Signed URL expira e é gerada por requisição — mesma
                          // decisão técnica já aplicada em `CardSetGalleryCard`
                          // (next/image exigiria domínio remoto configurado
                          // para uma URL que nem é estável).
                          // eslint-disable-next-line @next/next/no-img-element
                          <img src={set.logoUrl} alt="" className="h-full w-full object-contain" />
                        ) : (
                          <span className="text-xs font-medium text-muted-foreground">{getInitials(set.name)}</span>
                        )}
                      </div>
                    </DataTableCell>
                    <DataTableCell className="py-1">
                      <Link
                        href={`/catalogo/card-sets/${set.code}`}
                        onClick={(event) => event.stopPropagation()}
                        className="inline-flex flex-col leading-tight focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      >
                        <span className="text-foreground transition-colors hover:text-primary-ink hover:underline">
                          {set.name}
                        </span>
                        <span className="text-[11px] text-muted-foreground">{set.code}</span>
                      </Link>
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1">
                      <div className="flex flex-col items-center leading-tight">
                        <span className="text-muted-foreground">
                          {set.expansionName
                            ? set.expansionCode
                              ? `${set.expansionCode} - ${set.expansionName}`
                              : set.expansionName
                            : "—"}
                        </span>
                        <span className="text-[11px] text-muted-foreground">{set.gameName ?? "—"}</span>
                      </div>
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1">
                      <SetTypeTag setType={set.setType} />
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 text-muted-foreground">
                      {formatNumber(set.cardsCatalogados)} de {formatNumber(set.totalSetSize)}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1">
                      <StateBadge tone={imagensTone}>
                        {!semCartas && !imagensCompletas && <AlertTriangle className="mr-1 h-2.5 w-2.5" aria-hidden="true" />}
                        {formatNumber(set.cardsComImagem)} de {formatNumber(set.cardsCatalogados)}
                      </StateBadge>
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 text-muted-foreground">
                      {set.releaseDate ? formatarData(set.releaseDate) : "—"}
                    </DataTableCell>
                    <DataTableCell align="center" className="py-1 pr-4 last:pr-4">
                      <ChevronRight
                        className="mx-auto h-3.5 w-3.5 text-muted-foreground/50"
                        aria-hidden="true"
                      />
                    </DataTableCell>
                  </DataTableRow>
                );
              })}
            </tbody>
          </DataTable>
        )}
      </CardContent>

      {totalCount > 0 && (
        <div className="flex items-center justify-between border-t border-border px-4 py-3">
          <span className="text-sm text-muted-foreground">
            Mostrando{" "}
            <span className="font-medium text-foreground">{formatNumber(paginaAtual * CARD_SETS_PAGE_SIZE + 1)}</span>
            –
            <span className="font-medium text-foreground">
              {formatNumber(Math.min((paginaAtual + 1) * CARD_SETS_PAGE_SIZE, totalCount))}
            </span>{" "}
            de <span className="font-medium text-foreground">{formatNumber(totalCount)}</span>
          </span>
          <div className="flex items-center gap-1.5">
            <Button
              type="button"
              variant="outline"
              size="icon-sm"
              disabled={paginaAtual === 0}
              onClick={() => setPage((p) => p - 1)}
              aria-label="Página anterior"
            >
              <ChevronLeft className="h-3.5 w-3.5" />
            </Button>
            <span className="min-w-[2.5rem] text-center text-sm text-muted-foreground">
              {paginaAtual + 1}/{totalPages}
            </span>
            <Button
              type="button"
              variant="outline"
              size="icon-sm"
              disabled={paginaAtual >= totalPages - 1}
              onClick={() => setPage((p) => p + 1)}
              aria-label="Próxima página"
            >
              <ChevronRight className="h-3.5 w-3.5" />
            </Button>
          </div>
        </div>
      )}
    </Card>
  );
}
