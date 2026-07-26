import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

/**
 * Agrupa um bloco temático de configurações: título + descrição + divisor
 * superior + conteúdo (tipicamente uma ou mais SettingsRow). Padrão inspirado
 * no Supabase Dashboard — substitui o Card único de seção que empilhava tudo
 * sem hierarquia (ver revisão de design de 2026-07-26).
 */
export function SettingsSection({
  title,
  description,
  children,
  className,
  divider = true,
}: {
  title: string;
  description?: string;
  children: ReactNode;
  className?: string;
  divider?: boolean;
}) {
  return (
    <section className={cn("pb-6", divider && "border-t border-border pt-6", className)}>
      <h2 className="text-sm font-medium text-foreground">{title}</h2>
      {description && <p className="mt-0.5 text-xs text-muted-foreground">{description}</p>}
      <div className="mt-4">{children}</div>
    </section>
  );
}
