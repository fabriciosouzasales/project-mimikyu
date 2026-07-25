import Link from "next/link";
import { NAV_SECTIONS, type NavSection } from "./nav-config";
import { cn } from "@/lib/utils";

/** Trilha de ícones fixa (64px), sempre visível — nível 1 da navegação. */
export function PrimaryRail({ activeSection }: { activeSection: NavSection }) {
  return (
    <nav
      aria-label="Navegação principal"
      className="flex h-full w-16 shrink-0 flex-col items-center gap-1 border-r border-border bg-surface py-3"
    >
      <Link
        href="/"
        className="mb-2 flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-primary"
        aria-label="Ir para a página inicial"
      >
        <span className="sr-only">Project Mimikyu</span>
      </Link>

      {NAV_SECTIONS.map((section) => {
        const Icon = section.icon;
        const active = section.id === activeSection.id;
        return (
          <Link
            key={section.id}
            href={section.href}
            title={section.label}
            aria-current={active ? "page" : undefined}
            className={cn(
              "flex h-10 w-10 shrink-0 items-center justify-center rounded-md transition-colors",
              active
                ? "bg-primary/10 text-primary"
                : "text-muted-foreground hover:bg-surface-muted hover:text-foreground",
            )}
          >
            <Icon className="h-5 w-5" aria-hidden="true" />
            <span className="sr-only">{section.label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
