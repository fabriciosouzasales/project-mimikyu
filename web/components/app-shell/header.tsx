import { MobileNav } from "@/components/app-shell/mobile-nav";
import { ThemeToggle } from "@/components/theme-toggle";

/** Cabeçalho fixo do app shell: menu mobile (hambúrguer) + breadcrumb + ações globais. */
export function Header({ title }: { title: string }) {
  return (
    <header className="flex h-14 shrink-0 items-center justify-between border-b border-border bg-surface px-4">
      <div className="flex items-center gap-2">
        <MobileNav />
        <p className="text-sm font-medium text-muted-foreground">{title}</p>
      </div>
      <div className="flex items-center gap-2">
        <ThemeToggle />
      </div>
    </header>
  );
}
