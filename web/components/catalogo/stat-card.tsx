import type { LucideIcon } from "lucide-react";
import Link from "next/link";
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
 *
 * `dark:text-destructive-foreground` no ícone do tone="danger" (2026-07-31,
 * correção de contraste pedida por Fabrício): `--destructive` no tema
 * escuro é um vermelho bem escuro (20% de luminosidade, ver globals.css) —
 * quase invisível sobre o fundo também escuro do app. `--destructive-
 * foreground` no tema escuro já é quase branco (92%), reservado justamente
 * para ficar legível perto de vermelho — troca o ícone (não o selo de
 * fundo, que continua `bg-destructive/10`) por essa cor no tema escuro.
 * Afeta os dois cartões que usam `tone="danger"` hoje: "Pendências" (Visão
 * Geral) e "Sem Coleções" (Expansões).
 *
 * `href` opcional (2026-08-08, Sprint Gerencial 1 — drill-down da Visão
 * Geral): quando presente, o cartão inteiro vira um `Link` em vez de um
 * `Panel` estático, com o mesmo miolo visual — só ganha `hover:border-
 * foreground/20` como affordance de clique, já que nada aqui muda de cor
 * por padrão (selo de ícone já usa cor fixa, ver acima). Sem `href`, o
 * comportamento e o HTML renderizado são idênticos aos de antes desta
 * mudança — os cartões dos outros módulos (Jogos/Expansões/Cartas/Card
 * Sets/importar-imagens/importar-cartas) não usam a prop e continuam como
 * `Panel` puro.
 */
const STAT_CARD_CLASSES = "flex w-full items-start justify-between gap-3 p-3 sm:w-56";

export function StatCard({
  label,
  value,
  caption,
  icon: Icon,
  tone = "default",
  href,
}: {
  label: string;
  value: string | number;
  caption?: string;
  icon: LucideIcon;
  tone?: "default" | "danger";
  href?: string;
}) {
  const conteudo = (
    <>
      <div className="space-y-0.5">
        <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
        <p className="text-xl font-semibold text-foreground">{value}</p>
        {caption && <p className="text-xs text-muted-foreground">{caption}</p>}
      </div>
      <span
        className={cn(
          "flex h-7 w-7 shrink-0 items-center justify-center rounded-full",
          tone === "danger"
            ? "bg-destructive/10 text-destructive dark:text-destructive-foreground"
            : "bg-[#F7F5ED] text-[#2C2C2A]",
        )}
        aria-hidden="true"
      >
        <Icon className="h-3.5 w-3.5" />
      </span>
    </>
  );

  if (href) {
    return (
      <Link
        href={href}
        className={cn(
          STAT_CARD_CLASSES,
          "rounded-lg border border-border bg-surface transition-colors hover:border-foreground/20",
        )}
      >
        {conteudo}
      </Link>
    );
  }

  return <Panel className={STAT_CARD_CLASSES}>{conteudo}</Panel>;
}

export function StatsRow({ children }: { children: ReactNode }) {
  return <div className="flex flex-wrap gap-3">{children}</div>;
}
