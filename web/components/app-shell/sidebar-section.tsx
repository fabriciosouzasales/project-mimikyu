"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ChevronRight } from "lucide-react";
import { Collapsible, CollapsibleContent } from "@/components/ui/collapsible";
import { SidebarSectionItem } from "./sidebar-section-item";
import { findActiveSection, type NavSection } from "./nav-config";
import { cn } from "@/lib/utils";

/**
 * Um item principal da navegação. Clicar sempre navega E abre o submenu —
 * são a mesma ação (decisão de Fabrício), então não há Trigger separado do
 * Radix Collapsible: o `open` é só derivado da rota atual (controlado, sem
 * `onOpenChange`), e o link normal é que faz a navegação.
 */
export function SidebarSection({ section }: { section: NavSection }) {
  const pathname = usePathname();
  const activeSection = findActiveSection(pathname);
  const isActiveSection = activeSection.id === section.id;
  const hasChildren = !!section.children?.length;
  const Icon = section.icon;

  return (
    <div>
      <Link
        href={section.href}
        aria-current={isActiveSection && !hasChildren ? "page" : undefined}
        aria-expanded={hasChildren ? isActiveSection : undefined}
        className={cn(
          "relative flex h-10 items-center gap-3 overflow-hidden whitespace-nowrap rounded-md px-3 text-sm font-medium transition-colors",
          isActiveSection
            ? "bg-primary/10 text-primary"
            : "text-muted-foreground hover:bg-surface-muted hover:text-foreground",
        )}
      >
        {isActiveSection && (
          <span aria-hidden="true" className="absolute inset-y-1.5 left-0 w-0.5 rounded-full bg-primary" />
        )}
        <Icon className="h-5 w-5 shrink-0" aria-hidden="true" />
        <span className="flex-1 truncate">{section.label}</span>
        {hasChildren && (
          <ChevronRight
            className={cn("h-4 w-4 shrink-0 transition-transform", isActiveSection && "rotate-90")}
            aria-hidden="true"
          />
        )}
      </Link>

      {hasChildren && (
        <Collapsible open={isActiveSection}>
          <CollapsibleContent className="space-y-0.5 py-1">
            {section.children!.map((child) => (
              <SidebarSectionItem key={child.href} child={child} />
            ))}
          </CollapsibleContent>
        </Collapsible>
      )}
    </div>
  );
}
