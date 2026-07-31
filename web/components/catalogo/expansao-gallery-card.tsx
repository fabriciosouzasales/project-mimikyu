"use client";

import { Pencil, Trash2 } from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { getGameAccentColor } from "@/lib/catalogo/game-accent";
import { cn } from "@/lib/utils";
import type { ExpansaoWithLogo } from "@/lib/catalogo/queries";

/**
 * Card da galeria de Expansões — mesma linguagem visual do card de Card Set
 * (`card-set-gallery-card.tsx`): logo/iniciais em destaque, selo de cor do
 * Jogo, nome, código e uma contagem do que a entidade agrupa. Adaptado à
 * entidade Expansion:
 *
 * - Contagem de Card Sets em vez de Cartas (o que uma Expansão de fato
 *   agrupa).
 * - Logo (2026-07-31, Queries 2045-2047, pedido de Fabrício: "vamos incluir
 *   uma imagem para cada expansão") — mesmo padrão de `CardSetGalleryCard`:
 *   mostra `expansao.logoUrl` (URL assinada) quando existe, iniciais como
 *   reserva quando não.
 *
 * Ajuste 2026-07-31, mesmo dia (depois de ver as primeiras logos reais na
 * tela): a caixa da imagem deixou de ser `aspect-square` — logos de
 * Expansão são wordmarks horizontais (ex.: "Scarlet & Violet", "Sun & Moon"),
 * bem diferentes do símbolo quadrado/compacto de Card Set que motivou o
 * `aspect-square` original. `aspect-[2/1]` (proporção 2:1) sobra bem menos
 * espaço vazio acima/abaixo da arte real, mantendo `object-contain` (nunca
 * corta a imagem).
 *
 * Ajuste 2026-07-31 (pedido de Fabrício): clicar no card não abre mais o
 * Dialog de edição — navega para Coleções (`/catalogo/card-sets`) já
 * filtrada por Jogo e Expansão (`?game=&expansion=`, mesmos parâmetros que
 * `getCardSetsForCatalogo` já aceita — reaproveitado, não é rota nova).
 * Editar e excluir viram ações rápidas (ícones de lápis/lixeira) no canto
 * inferior direito, na mesma altura do contador de coleções — mesmo padrão
 * de "ação rápida" já usado na tabela de Jogos. Ambos os ícones sem borda
 * (`variant="ghost"`, pedido explícito de Fabrício) — cor explícita em cada
 * um (`text-foreground`/`text-destructive`, com variante para tema escuro),
 * já que `ghost` não tem cor de texto própria (mesmo cuidado já aplicado ao
 * variant `outline` — ver `button.tsx`).
 *
 * Estrutura: o card deixou de ser um único `<button>`/`<a>` clicável — é um
 * `<div>` com um `<Link>` cobrindo toda a área (`absolute inset-0`), e os
 * botões de ação ficam num bloco `relative` acima dele (`z-10`), sempre
 * depois no DOM e com stacking mais alto, então interceptam o clique antes
 * do Link chegar neles. Evita aninhar `<button>` dentro de `<a>` (HTML
 * inválido, quebra navegação por teclado/leitor de tela).
 */
function getInitials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0]?.toUpperCase() ?? "")
    .join("");
}

export function ExpansaoGalleryCard({
  expansao,
  highlighted,
  onEdit,
  onQuickDelete,
}: {
  expansao: ExpansaoWithLogo;
  highlighted: boolean;
  onEdit: (id: string) => void;
  onQuickDelete: (id: string) => void;
}) {
  const accent = getGameAccentColor(expansao.gameCode || expansao.gameName);

  return (
    <div
      className={cn(
        "group relative flex flex-col overflow-hidden rounded-lg border border-border bg-surface transition-colors hover:border-primary/40",
        highlighted && "border-primary/40 bg-primary/5",
      )}
    >
      <Link
        href={`/catalogo/card-sets?game=${expansao.gameCode}&expansion=${expansao.code}`}
        aria-label={`Ver coleções de ${expansao.name}`}
        className="absolute inset-0 z-0 rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      />

      <div className="flex aspect-[2/1] items-center justify-center bg-surface-muted">
        {expansao.logoUrl ? (
          // Signed URL expira e é gerada por requisição — mesma decisão de
          // CardSetGalleryCard: <img> simples em vez de next/image.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={expansao.logoUrl} alt="" className="h-full w-full object-contain p-3" />
        ) : (
          <span className="font-heading text-2xl font-medium text-muted-foreground">{getInitials(expansao.name)}</span>
        )}
      </div>
      <div className="space-y-1 p-3">
        <div className="flex items-center gap-1.5">
          <span className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ backgroundColor: accent }} aria-hidden="true" />
          <span className="truncate text-[11px] text-muted-foreground">{expansao.gameName}</span>
        </div>
        <p className="truncate text-sm font-medium text-foreground">{expansao.name}</p>
        <div className="flex items-center justify-between gap-2">
          <p className="text-xs text-muted-foreground">
            {expansao.code} · {expansao.totalCardSets} {expansao.totalCardSets === 1 ? "coleção" : "coleções"}
          </p>
          <div className="relative z-10 flex items-center gap-0.5">
            <Button
              type="button"
              variant="ghost"
              size="icon-sm"
              className="text-foreground"
              aria-label={`Editar ${expansao.name}`}
              onClick={(event) => {
                event.preventDefault();
                event.stopPropagation();
                onEdit(expansao.id);
              }}
            >
              <Pencil className="h-3 w-3" />
            </Button>
            <Button
              type="button"
              variant="ghost"
              size="icon-sm"
              className="text-destructive hover:bg-destructive/10 hover:text-destructive dark:text-destructive-foreground dark:hover:text-destructive-foreground"
              aria-label={`Excluir ${expansao.name}`}
              onClick={(event) => {
                event.preventDefault();
                event.stopPropagation();
                onQuickDelete(expansao.id);
              }}
            >
              <Trash2 className="h-3 w-3" />
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
