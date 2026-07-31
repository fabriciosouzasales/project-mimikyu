import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { Header } from "@/components/app-shell/header";
import { Sidebar } from "@/components/app-shell/sidebar";
import { createClient } from "@/lib/supabase/server";

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
  const supabase = await createClient();
  const { data: isAdmin } = await supabase.rpc("is_admin");

  return (
    <div className="flex h-dvh overflow-hidden bg-background">
      <Sidebar isAdmin={!!isAdmin} />
      <div className="flex min-w-0 flex-1 flex-col">
        <Header title={title} icon={icon} isAdmin={!!isAdmin} />
        <main className="flex-1 overflow-y-auto p-6">{children}</main>
      </div>
    </div>
  );
}
