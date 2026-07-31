import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Estado vazio padrão — Fundação visual, Ciclo B (2026-07-30, ver STD-004).
 * Substitui o `<div className="flex flex-col items-center gap-1 py-8/10
 * text-center">` reescrito à mão em `JogosTable`, `AtividadeRecente`,
 * `Distribuicoes` e `UsersTable`. `icon` é opcional — as telas atuais não
 * usam ícone no vazio (decisão preservada); disponível para quando um
 * estado vazio precisar de mais contexto visual.
 */
export function EmptyState({
  icon: Icon,
  title,
  description,
  className,
}: {
  icon?: LucideIcon;
  title: string;
  description?: string;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col items-center gap-1 py-10 text-center", className)}>
      {Icon && <Icon className="mb-2 h-8 w-8 text-muted-foreground/50" aria-hidden="true" />}
      <p className="text-sm text-foreground">{title}</p>
      {description && <p className="text-xs text-muted-foreground">{description}</p>}
    </div>
  );
}
