import { cva, type VariantProps } from "class-variance-authority";
import type { HTMLAttributes, ReactNode } from "react";
import { cn } from "@/lib/utils";

/**
 * Primitives de composição de página — Fundação visual, Ciclo B
 * (2026-07-30, ver STD-004). Substituem o `<h1 className="font-heading...">`
 * + `mx-auto max-w-*` que cada página reescrevia à mão. Deliberadamente
 * pequenas: nenhuma delas guarda estado ou lógica, só normalizam espaçamento
 * e hierarquia — a página continua decidindo sua própria estrutura interna.
 */
const pageContainerVariants = cva("mx-auto space-y-4", {
  variants: {
    width: {
      /** Telas de listagem/tabela padrão (Jogos, Expansões, Card Sets). */
      default: "max-w-6xl",
      /** Telas com mais colunas de conteúdo (ex.: Visão Geral do Catálogo). */
      wide: "max-w-7xl",
      /** Sem limite de largura — usar só quando o conteúdo precisa da tela inteira. */
      full: "max-w-none",
      /** Formulários de configuração de coluna única (Perfil, Configurações). */
      settings: "max-w-2xl",
    },
  },
  defaultVariants: { width: "default" },
});

export interface PageContainerProps extends HTMLAttributes<HTMLDivElement>, VariantProps<typeof pageContainerVariants> {}

export function PageContainer({ className, width, ...props }: PageContainerProps) {
  return <div className={cn(pageContainerVariants({ width }), className)} {...props} />;
}

export function PageHeader({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("flex items-center justify-between gap-3", className)} {...props} />;
}

/** Agrupa título + descrição — filho de `PageHeader`, ao lado de `PageActions`. */
export function PageHeading({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("space-y-0.5", className)} {...props} />;
}

export function PageTitle({ className, ...props }: HTMLAttributes<HTMLHeadingElement>) {
  return <h1 className={cn("font-heading text-xl font-medium text-foreground", className)} {...props} />;
}

export function PageDescription({ className, ...props }: HTMLAttributes<HTMLParagraphElement>) {
  return <p className={cn("text-sm text-muted-foreground", className)} {...props} />;
}

/** Ações primárias da página (ex.: botão de criação) — filho de `PageHeader`, alinhado à direita. */
export function PageActions({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("flex shrink-0 items-center gap-2", className)} {...props} />;
}

/** Linha de busca/filtros abaixo do cabeçalho — só renderiza quando a página tem algo a filtrar. */
export function PageToolbar({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("flex flex-wrap items-center gap-2", className)} {...props} />;
}

/**
 * Bloco temático dentro da página (título + conteúdo), para páginas com mais
 * de uma seção fora do padrão Settings (que já tem `SettingsSection`
 * própria). Sem uso real ainda nesta rodada — documentado para consistência
 * quando a primeira página multi-seção fora de Configurações precisar dele.
 */
export function PageSection({
  title,
  description,
  children,
  className,
}: {
  title: string;
  description?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={cn("space-y-3", className)}>
      <div className="space-y-0.5">
        <h2 className="text-sm font-medium text-foreground">{title}</h2>
        {description && <p className="text-xs text-muted-foreground">{description}</p>}
      </div>
      {children}
    </section>
  );
}
