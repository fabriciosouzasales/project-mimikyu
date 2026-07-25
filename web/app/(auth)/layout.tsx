import type { ReactNode } from "react";
import { ThemeToggle } from "@/components/theme-toggle";

/** Layout dedicado às telas de autenticação — sem sidebar, foco total no formulário. */
export default function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-dvh flex-col bg-background">
      <header className="flex h-14 items-center justify-between px-4">
        <div className="flex items-center gap-2">
          <div className="h-6 w-6 rounded-md bg-primary" aria-hidden="true" />
          <span className="text-sm font-semibold">Project Mimikyu</span>
        </div>
        <ThemeToggle />
      </header>
      <main className="flex flex-1 items-center justify-center p-4">
        <div className="w-full max-w-sm">{children}</div>
      </main>
    </div>
  );
}
