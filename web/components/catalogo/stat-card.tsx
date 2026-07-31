import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { Panel } from "@/components/catalogo/panel";
import { cn } from "@/lib/utils";

/**
 * Cartão de indicador — padrão introduzido na tela Jogos (2026-07-31), a
 * partir de referência visual anexada por Fabrício (linha de cartões antes
 * da tabela, cada um com rótulo, número em destaque, legenda opcional e um
 * selo de ícone colorido). Mesma superfície `Panel` já usada pelo módulo
 * Catálogo Editorial — sem introduzir uma segunda linguagem de card.
 *
 * Ajuste fino (mesmo dia, pedido de Fabrício): cartões mais baixos (menos
 * padding e fonte menor no número) e selo de ícone com cor fixa — fundo
 * #F7F5ED (trocado de #D7CFAC), ícone #2C2C2A — igual em todos os
 * cartões. Substitui a variação por "tone" (uma cor por tipo de métrica)
 * que existia antes; removida porque a instrução explícita foi
 * uniformizar, não diferenciar.
 *
 * Reservado para reuso nas telas de Expansão e Card Set depois da validação
 * desta primeira aplicação (Jogos).
 *
 * `tone="danger"` (2026-07-31, pedido de Fabrício na Visão Geral: "Pendências
 * deve ter ícone vermelho") — única exceção ao selo uniforme #F7F5ED/#2C2C2A.
 * Opcional, não usado por Jogos — mantém os cartões existentes intocados.
 */
export function StatCard({
  label,
  value,
  caption,
  icon: Icon,
  tone = "default",
}: {
  label: string;
  value: string | number;
  caption?: string;
  icon: LucideIcon;
  tone?: "default" | "danger";
}) {
  return (
    <Panel className="flex w-full items-start justify-between gap-3 p-3 sm:w-56">
      <div className="space-y-0.5">
        <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
        <p className="text-xl font-semibold text-foreground">{value}</p>
        {caption && <p className="text-xs text-muted-foreground">{caption}</p>}
      </div>
      <span
        className={cn(
          "flex h-7 w-7 shrink-0 items-center justify-center rounded-full",
          tone === "danger" ? "bg-destructive/10 text-destructive" : "bg-[#F7F5ED] text-[#2C2C2A]",
        )}
        aria-hidden="true"
      >
        <Icon className="h-3.5 w-3.5" />
      </span>
    </Panel>
  );
}

export function StatsRow({ children }: { children: ReactNode }) {
  return <div className="flex flex-wrap gap-3">{children}</div>;
}
