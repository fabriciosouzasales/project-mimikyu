"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { NavSection } from "./nav-config";
import { cn } from "@/lib/utils";

/** Submenu contextual (nível 2) — só existe quando a seção ativa tem filhos. */
export function SecondaryPanel({ section }: { section: NavSection }) {
  const pathname = usePathname();

  if (!section.children || section.children.length === 0) {
    return null;
  }

  return (
    <div className="flex h-full w-60 shrink-0 flex-col border-r border-border bg-surface">
      <div className="flex h-14 shrink-0 items-center border-b border-border px-4">
        <span className="truncate text-sm font-semibold">{section.label}</span>
      </div>
      <nav className="flex-1 space-y-0.5 p-2" aria-label={`Submenu de ${section.label}`}>
        {section.children.map((child) => {
          const active = pathname === child.href;
          return (
            <Link
              key={child.href}
              href={child.href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "block truncate rounded-md px-3 py-1.5 text-sm transition-colors",
                active
                  ? "bg-primary/10 font-medium text-primary"
                  : "text-muted-foreground hover:bg-surface-muted hover:text-foreground",
              )}
            >
              {child.label}
            </Link>
          );
        })}
      </nav>
    </div>
  );
}
