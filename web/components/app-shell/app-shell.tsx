import type { ReactNode } from "react";
import { Header } from "@/components/app-shell/header";
import { Sidebar } from "@/components/app-shell/sidebar";

/** Casca visual das telas autenticadas (sidebar + header + conteúdo). */
export function AppShell({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="flex h-dvh overflow-hidden bg-background">
      <Sidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <Header title={title} />
        <main className="flex-1 overflow-y-auto p-6">{children}</main>
      </div>
    </div>
  );
}
