import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

/**
 * Linha de configuração em duas colunas: rótulo + descrição à esquerda,
 * valor/controle à direita. Empilha em uma coluna só em telas estreitas.
 * Uso dentro de SettingsSection.
 */
export function SettingsRow({
  label,
  description,
  children,
  className,
}: {
  label: string;
  description?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "grid grid-cols-1 gap-3 border-t border-border py-3.5 sm:grid-cols-[220px_minmax(0,1fr)] sm:items-start sm:gap-4",
        className,
      )}
    >
      <div>
        <p className="text-sm font-medium text-foreground">{label}</p>
        {description && <p className="mt-0.5 text-xs text-muted-foreground">{description}</p>}
      </div>
      <div>{children}</div>
    </div>
  );
}
