import type { HTMLAttributes } from "react";
import { cn } from "@/lib/utils";

/**
 * Bloco de carregamento — Fundação visual, Ciclo B (2026-07-30, ver
 * STD-004). `animate-pulse` é utilitário nativo do Tailwind (sem token
 * novo). Sem uso real ainda no piloto de Expansões (dado é buscado no
 * servidor, antes da renderização — não há um vazio de carregamento no
 * cliente); disponível para quando uma tela buscar dados no cliente.
 */
export function Skeleton({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("animate-pulse rounded-md bg-muted", className)} {...props} />;
}
