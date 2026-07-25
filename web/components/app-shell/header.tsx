import { ThemeToggle } from "@/components/theme-toggle";

/** Cabeçalho fixo do app shell: breadcrumb (placeholder na Etapa 0) + ações globais. */
export function Header({ title }: { title: string }) {
  return (
    <header className="flex h-14 shrink-0 items-center justify-between border-b border-border bg-surface px-4">
      <p className="text-sm font-medium text-muted-foreground">{title}</p>
      <div className="flex items-center gap-2">
        <ThemeToggle />
      </div>
    </header>
  );
}
