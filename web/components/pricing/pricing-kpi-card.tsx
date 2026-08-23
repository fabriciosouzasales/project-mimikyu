import type { LucideIcon } from "lucide-react";
import Link from "next/link";
import { Panel } from "@/components/catalogo/panel";
import { cn } from "@/lib/utils";

/**
 * Cartão de KPI dedicado à Visão Geral de Pricing v3 (2026-08-23, redesenho
 * visual pedido por Fabrício). Deliberadamente NÃO reaproveita
 * `components/catalogo/stat-card.tsx` — aquele componente documenta
 * explicitamente que sua uniformidade (padding reduzido, selo de ícone de
 * tamanho fixo) é uma escolha deliberada de outra rodada ("a instrução
 * explícita foi uniformizar, não diferenciar"), e reusá-lo aqui quebraria
 * esse contrato para todas as outras telas que o usam sem alteração
 * (Jogos, Expansões, Card Sets). A diretriz #2 deste redesenho pede o
 * oposto para esta tela especificamente: "mais presença, respiro e
 * hierarquia", "evitar aparência de simples contadores" — daí um
 * componente novo, mesma superfície `Panel`, dimensões maiores.
 *
 * `progress` (opcional): barra de progresso REAL — só usada pelo KPI
 * "Cobertura de Preços" (`coverage_pct` vindo direto do banco), nunca uma
 * barra decorativa. Cor da barra segue `tone` (default = dourado da marca,
 * warning = usado quando a cobertura está abaixo do limiar de atenção).
 */
export function PricingKpiCard({
  label,
  value,
  caption,
  icon: Icon,
  href,
  progress,
}: {
  label: string;
  value: string | number;
  caption?: string;
  icon: LucideIcon;
  href?: string;
  progress?: { pct: number; tone: "default" | "warning" };
}) {
  const conteudo = (
    <>
      <div className="flex items-start justify-between gap-3">
        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-primary/15 text-primary-ink" aria-hidden="true">
          <Icon className="h-4 w-4" />
        </span>
      </div>
      <p className="mt-2 text-2xl font-semibold tabular-nums text-foreground">{value}</p>
      {caption && <p className="mt-0.5 text-xs text-muted-foreground">{caption}</p>}
      {progress && (
        <div className="mt-3 h-1.5 w-full overflow-hidden rounded-full bg-surface-muted">
          <div
            className={cn("h-full rounded-full transition-[width]", progress.tone === "warning" ? "bg-warning" : "bg-primary")}
            style={{ width: `${Math.min(100, Math.max(0, progress.pct))}%` }}
          />
        </div>
      )}
    </>
  );

  const classes = "flex w-full flex-col p-4 sm:p-5";

  if (href) {
    return (
      <Link href={href} className={cn(classes, "rounded-lg border border-border bg-surface transition-colors hover:border-foreground/20")}>
        {conteudo}
      </Link>
    );
  }

  return <Panel className={classes}>{conteudo}</Panel>;
}
