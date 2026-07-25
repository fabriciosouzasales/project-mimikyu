"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { NavChild } from "./nav-config";
import { cn } from "@/lib/utils";

/** Item de submenu — recuado, dentro da própria barra (sem menus flutuantes). */
export function SidebarSectionItem({ child }: { child: NavChild }) {
  const pathname = usePathname();
  const active = pathname === child.href;

  return (
    <Link
      href={child.href}
      aria-current={active ? "page" : undefined}
      className={cn(
        "ml-9 flex items-center whitespace-nowrap rounded-md px-3 py-1.5 text-sm transition-colors",
        active
          ? "bg-primary/10 font-medium text-primary"
          : "text-muted-foreground hover:bg-surface-muted hover:text-foreground",
      )}
    >
      {child.label}
    </Link>
  );
}
