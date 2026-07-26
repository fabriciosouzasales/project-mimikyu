"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import * as DialogPrimitive from "@radix-ui/react-dialog";
import { Menu, X } from "lucide-react";
import { findActiveSection, getVisibleNavSections } from "./nav-config";
import { SidebarFooter } from "./sidebar-footer";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

/**
 * Navegação mobile: nada de hover (não existe em touch) — abre como Drawer
 * (Radix Dialog estilizado como painel lateral), acionado pelo botão
 * hambúrguer no header. Fecha ao navegar ou ao tocar fora/Esc (padrão do
 * Radix Dialog).
 *
 * Repete parte da renderização de `SidebarSection`/`SidebarSectionItem` em
 * vez de reutilizá-los diretamente: aqui a lista está sempre "expandida"
 * (sem a lógica de largura/hover), então forçar o mesmo componente exigiria
 * mais props condicionais do que vale a pena para dois usos só. Se um
 * terceiro contexto aparecer, factoro num componente compartilhado.
 */
export function MobileNav({ isAdmin }: { isAdmin: boolean }) {
  const [open, setOpen] = useState(false);
  const pathname = usePathname();
  const activeSection = findActiveSection(pathname);
  const sections = getVisibleNavSections(isAdmin);

  return (
    <DialogPrimitive.Root open={open} onOpenChange={setOpen}>
      <DialogPrimitive.Trigger asChild>
        <Button variant="ghost" size="icon" className="md:hidden" aria-label="Abrir menu">
          <Menu className="h-5 w-5" />
        </Button>
      </DialogPrimitive.Trigger>

      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-40 bg-foreground/20 data-[state=open]:animate-overlay-in data-[state=closed]:animate-overlay-out" />
        <DialogPrimitive.Content className="fixed inset-y-0 left-0 z-50 flex w-72 flex-col bg-surface shadow-panel data-[state=open]:animate-drawer-in data-[state=closed]:animate-drawer-out">
          <div className="flex h-14 shrink-0 items-center justify-between border-b border-border px-4">
            <DialogPrimitive.Title className="text-sm font-semibold">Project Mimikyu</DialogPrimitive.Title>
            <DialogPrimitive.Close asChild>
              <Button variant="ghost" size="icon" aria-label="Fechar menu">
                <X className="h-4 w-4" />
              </Button>
            </DialogPrimitive.Close>
          </div>

          <nav className="flex-1 space-y-1 overflow-y-auto p-2" aria-label="Navegação principal (mobile)">
            {sections.map((section) => {
              const Icon = section.icon;
              const isActive = activeSection.id === section.id;
              return (
                <div key={section.id}>
                  <Link
                    href={section.href}
                    onClick={() => setOpen(false)}
                    aria-current={isActive ? "page" : undefined}
                    className={cn(
                      "flex h-10 items-center gap-3 rounded-md px-3 text-sm transition-colors",
                      isActive
                        ? "bg-accent font-semibold text-foreground"
                        : "font-medium text-muted-foreground hover:bg-surface-muted hover:text-foreground",
                    )}
                  >
                    <Icon className="h-5 w-5 shrink-0" aria-hidden="true" />
                    <span className="truncate">{section.label}</span>
                  </Link>

                  {isActive && section.children && (
                    <div className="space-y-0.5 py-1">
                      {section.children.map((child) => (
                        <Link
                          key={child.href}
                          href={child.href}
                          onClick={() => setOpen(false)}
                          aria-current={pathname === child.href ? "page" : undefined}
                          className={cn(
                            "ml-9 flex items-center rounded-md px-3 py-1.5 text-sm transition-colors",
                            pathname === child.href
                              ? "bg-accent font-semibold text-foreground"
                              : "text-muted-foreground hover:bg-surface-muted hover:text-foreground",
                          )}
                        >
                          {child.label}
                        </Link>
                      ))}
                    </div>
                  )}
                </div>
              );
            })}
          </nav>

          <SidebarFooter />
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}
