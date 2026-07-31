"use client";

import { Pencil, Trash2 } from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { getGameAccentColor } from "@/lib/catalogo/game-accent";
import { cn } from "@/lib/utils";
import type { CardSetWithLogo } from "@/app/catalogo/card-sets/catalogo-actions";

/**
 * Card da galeria — spec aprovada 2026-07-31. Nível 1 (arte/logo) sempre
 * maior que o texto; sem logo cadastrada, iniciais do nome substituem a
 * arte (nunca um ícone genérico solto) — decisão tomada aqui mesmo, sem
 * reabrir discussão de UX, para o caso não coberto explicitamente pela
 * especificação. Sem data de criação/atualização nem qualquer metadado
 * administrativo — decisão já aprovada (Nível 4, quase invisível).
 *
 * Ajuste 2026-07-31 (pedido de Fabrício: "faça todos os ajustes necessários
 * para manter o mesmo padrão da página Expansões"): mesma estrutura de
 * `ExpansaoGalleryCard` — o card deixa de ser um único `<Link>` clicável e
 * passa a ser um `<div>` com um `<Link>` cobrindo toda a área (`absolute
 * inset-0`) para a rota de detalhe, e os botões de ação rápida (editar/
 * excluir, ícones sem borda) ficam num bloco `relative z-10` acima dele,
 * interceptando o clique antes do Link. Evita aninhar `<button>` dentro de
 * `<a>` (mesmo cuidado já aplicado em `ExpansaoGalleryCard`).
 *
 * Padding da caixa de imagem reduzido de `p-4` para `p-3` (mesmo valor de
 * `ExpansaoGalleryCard`) — uniformiza a "respiração" da arte entre as duas
 * galerias. `aspect-square` (não `aspect-[2/1]`) é mantido deliberadamente:
 * diferente da logo de Expansão (wordmark horizontal), a logo de Card Set é
 * o símbolo quadrado/compacto que originou o `aspect-square` do padrão (ver
 * `05-modelo-de-dados.md`, seção Set) — aplicar a proporção 2:1 aqui
 * sobraria espaço vazio ao redor de uma arte que já é quadrada.
 */
function getInitials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0]?.toUpperCase() ?? "")
    .join("");
}

export function CardSetGalleryCard({
  cardSet,
  highlighted,
  onEdit,
  onQuickDelete,
}: {
  cardSet: CardSetWithLogo;
  highlighted: boolean;
  onEdit: (id: string) => void;
  onQuickDelete: (id: string) => void;
}) {
  const accent = getGameAccentColor(cardSet.gameCode || cardSet.gameName);

  return (
    <div
      className={cn(
        "group relative flex flex-col overflow-hidden rounded-lg border border-border bg-surface transition-colors hover:border-primary/40",
        highlighted && "border-primary/40 bg-primary/5",
      )}
    >
      <Link
        href={`/catalogo/card-sets/${cardSet.code}`}
        aria-label={`Ver detalhe de ${cardSet.name}`}
        className="absolute inset-0 z-0 rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      />

      <div className="flex aspect-square items-center justify-center bg-surface-muted">
        {cardSet.logoUrl ? (
          // Signed URL expira e é gerada por requisição — next/image exigiria
          // configurar domínio remoto para uma URL que nem é estável; <img>
          // simples evita esse acoplamento sem perder o essencial (a imagem
          // aparece). Ver relatório de decisões técnicas.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={cardSet.logoUrl} alt="" className="h-full w-full object-contain p-3" />
        ) : (
          <span className="font-heading text-2xl font-medium text-muted-foreground">
            {getInitials(cardSet.name)}
          </span>
        )}
      </div>
      <div className="space-y-1 p-3">
        <div className="flex items-center gap-1.5">
          <span className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ backgroundColor: accent }} aria-hidden="true" />
          <span className="truncate text-[11px] text-muted-foreground">{cardSet.gameName}</span>
        </div>
        <p className="truncate text-sm font-medium text-foreground">{cardSet.name}</p>
        <div className="flex items-center justify-between gap-2">
          <p className="text-xs text-muted-foreground">
            {cardSet.code} · {cardSet.cardsCatalogados} {cardSet.cardsCatalogados === 1 ? "carta" : "cartas"}
          </p>
          <div className="relative z-10 flex items-center gap-0.5">
            <Button
              type="button"
              variant="ghost"
              size="icon-sm"
              className="text-foreground"
              aria-label={`Editar ${cardSet.name}`}
              onClick={(event) => {
                event.preventDefault();
                event.stopPropagation();
                onEdit(cardSet.id);
              }}
            >
              <Pencil className="h-3 w-3" />
            </Button>
            <Button
              type="button"
              variant="ghost"
              size="icon-sm"
              className="text-destructive hover:bg-destructive/10 hover:text-destructive dark:text-destructive-foreground dark:hover:text-destructive-foreground"
              aria-label={`Excluir ${cardSet.name}`}
              onClick={(event) => {
                event.preventDefault();
                event.stopPropagation();
                onQuickDelete(cardSet.id);
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
