"use client";

import Link from "next/link";
import { ChevronLeft, ChevronRight, Search } from "lucide-react";
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
import type { CardSetOverviewRow } from "@/lib/catalogo/queries";

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
 */
const CARD_SETS_PAGE_SIZE = 10;

export function CardSetsTable({ cardSets }: { cardSets: CardSetOverviewRow[] }) {
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(0);

  const filtrados = useMemo(() => {
    const termo = query.trim().toLowerCase();
    if (!termo) return cardSets;
    return cardSets.filter((set) =>
      [set.name, set.code, set.expansionName, set.gameName]
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
            placeholder="Buscar por Card Set, Jogo ou Expansão…"
            className="h-9 bg-surface-muted pl-9 text-xs"
            aria-label="Buscar Card Set"
          />
        </div>
      </div>

      <CardContent density="compact" className="px-0 pb-0">
        {cardSets.length === 0 ? (
          <EmptyState
            title="Nenhum Card Set catalogado ainda"
            description="Os Card Sets aparecem aqui assim que forem cadastrados."
          />
        ) : filtrados.length === 0 ? (
          <EmptyState title={`Nenhum resultado para "${query}"`} description="Tente outro nome ou código." />
        ) : (
          <DataTable>
            <DataTableHead>
              <DataTableHeadRow className="bg-surface-muted">
                <DataTableHeadCell align="center" className="pl-4">
                  Card Set
                </DataTableHeadCell>
                <DataTableHeadCell align="center">Jogo / Expansão</DataTableHeadCell>
                <DataTableHeadCell align="center">Tipo</DataTableHeadCell>
                <DataTableHeadCell align="center">Cartas</DataTableHeadCell>
                <DataTableHeadCell align="center">Imagens</DataTableHeadCell>
                <DataTableHeadCell align="center">Logo</DataTableHeadCell>
                <DataTableHeadCell align="center" className="pr-4 last:pr-4" />
              </DataTableHeadRow>
            </DataTableHead>
            <tbody>
              {itensPagina.map((set) => (
                <DataTableRow key={set.code}>
                  <DataTableCell className="pl-4">
                    <Link
                      href={`/catalogo/card-sets/${set.code}`}
                      className="inline-flex flex-col leading-tight focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                      <span className="text-primary hover:underline">{set.name}</span>
                      <span className="text-[11px] text-muted-foreground">{set.code}</span>
                    </Link>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <div className="flex flex-col items-center leading-tight">
                      <span className="text-muted-foreground">{set.expansionName ?? "—"}</span>
                      <span className="text-[11px] text-muted-foreground">{set.gameName ?? "—"}</span>
                    </div>
                  </DataTableCell>
                  <DataTableCell align="center">
                    <SetTypeTag setType={set.setType} />
                  </DataTableCell>
                  <DataTableCell align="center" className="text-muted-foreground">
                    {set.totalSetSize}
                  </DataTableCell>
                  <DataTableCell align="center">
                    {set.temImagensCompletas ? (
                      <StateBadge tone="success">Completas</StateBadge>
                    ) : (
                      <StateBadge tone="warning">Pendente</StateBadge>
                    )}
                  </DataTableCell>
                  <DataTableCell align="center" className="text-muted-foreground">
                    {set.temLogo ? "Cadastrada" : "—"}
                  </DataTableCell>
                  <DataTableCell align="center" className="pr-4 last:pr-4">
                    <Link
                      href={`/catalogo/card-sets/${set.code}`}
                      aria-label={`Ver detalhe de ${set.name}`}
                      className="inline-flex justify-center text-muted-foreground/50 hover:text-muted-foreground focus-visible:outline-none"
                    >
                      <ChevronRight className="h-3.5 w-3.5" />
                    </Link>
                  </DataTableCell>
                </DataTableRow>
              ))}
            </tbody>
          </DataTable>
        )}
      </CardContent>

      {totalCount > 0 && (
        <div className="flex items-center justify-between border-t border-border px-4 py-3">
          <span className="text-sm text-muted-foreground">
            Mostrando <span className="font-medium text-foreground">{paginaAtual * CARD_SETS_PAGE_SIZE + 1}</span>–
            <span className="font-medium text-foreground">
              {Math.min((paginaAtual + 1) * CARD_SETS_PAGE_SIZE, totalCount)}
            </span>{" "}
            de <span className="font-medium text-foreground">{totalCount}</span>
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
