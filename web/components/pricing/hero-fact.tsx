import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * `HeroFact` — bloco label+valor (+ barra de progresso opcional) usado na
 * faixa de fatos-chave dos Heros gerenciais de Pricing. Extraído de
 * `pricing-overview-hero.tsx` (2026-08-23) no momento em que
 * `pricing-fontes-hero.tsx` virou o segundo consumidor — mesma grade visual
 * (ícone 3.5, label 10px maiúsculo, valor 18px semibold tabular) precisa
 * ficar idêntica nos dois Heros sem duplicar o componente; qualquer ajuste
 * futuro de estilo do Hero (ex.: v3.6 reduziu altura/opacidade da barra)
 * passa a valer para ambos automaticamente.
 */
export function HeroFact({
  icon: Icon,
  label,
  value,
  valueClassName,
  progressPct,
}: {
  icon: LucideIcon;
  label: string;
  value: string;
  valueClassName?: string;
  progressPct?: number;
}) {
  return (
    <div className="space-y-1">
      <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground">
        <Icon className="h-3.5 w-3.5" aria-hidden="true" />
        {label}
      </p>
      <p className={cn("text-lg font-semibold tabular-nums text-foreground", valueClassName)}>{value}</p>
      {progressPct !== undefined && (
        <div className="h-1 w-3/4 overflow-hidden rounded-full bg-surface-muted">
          <div
            className="h-full rounded-full bg-primary/60 transition-[width]"
            style={{ width: `${Math.min(100, Math.max(0, progressPct))}%` }}
          />
        </div>
      )}
    </div>
  );
}
