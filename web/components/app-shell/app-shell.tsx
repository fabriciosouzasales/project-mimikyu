import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { Header } from "@/components/app-shell/header";
import { Sidebar } from "@/components/app-shell/sidebar";
import { getCachedIsAdmin } from "@/lib/supabase/request-auth-cache";

/**
 * Casca visual das telas autenticadas (sidebar + header + conteúdo).
 * Busca o status administrativo uma única vez aqui (via is_admin(), ver
 * ADR-021) e repassa para Sidebar e Header — evita duplicar a chamada em
 * cada um. Isso é só para decidir o que MOSTRAR no menu; a autorização de
 * verdade é sempre revalidada em cada página/função do lado do servidor.
 *
 * `icon` (2026-07-31, pedido de Fabrício: "o ícone do menu deve ser mantido
 * antes do título da página") — opcional, repassado ao `Header`. Primeira
 * aplicação em /catalogo/expansoes (mesmo ícone do item de menu, `Layers`);
 * as demais telas não passam `icon` e continuam idênticas.
 */
export async function AppShell({
  title,
  icon,
  children,
}: {
  title: string;
  icon?: LucideIcon;
  children: ReactNode;
}) {
  // getCachedIsAdmin() (Incremento 1 de performance, 2026-08-14): mesma
  // chamada de sempre (rpc("is_admin")), memoizada por requisição — reusa o
  // resultado já obtido por requireCatalogoAdmin() (quando a página passa por
  // ele) em vez de refazer a chamada de rede. Ver
  // lib/supabase/request-auth-cache.ts.
  const { data: isAdmin } = await getCachedIsAdmin();

  return (
    <div className="flex h-dvh overflow-hidden bg-background print:h-auto print:overflow-visible">
      <Sidebar isAdmin={!!isAdmin} />
      <div className="flex min-w-0 flex-1 flex-col print:overflow-visible">
        <Header title={title} icon={icon} isAdmin={!!isAdmin} />
        {/* print:overflow-visible/print:p-0: sem isso, o corte de altura (h-dvh/overflow-y-auto,
            necessário para o scroll normal da tela) clipa o conteúdo ao imprimir — a Central
            de Relatórios (2026-08-09) é o primeiro uso real de impressão no projeto. */}
        <main className="flex-1 overflow-y-auto p-6 print:overflow-visible print:p-0">{children}</main>
      </div>
    </div>
  );
}
