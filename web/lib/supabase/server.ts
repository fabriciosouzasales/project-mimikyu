import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { cookies } from "next/headers";

/**
 * Cliente Supabase para uso em Server Components, Route Handlers e Server Actions.
 * Lê/escreve a sessão via cookies do Next.js — nunca mantém a sessão em memória
 * compartilhada entre requisições de usuários diferentes.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        // Anotação explícita necessária (pré-existente, não introduzida pelo
        // Ciclo 2 — arquivo nunca tocado nesta rodada, confirmado via `git
        // log`): mesma causa de web/lib/supabase/middleware.ts — a sobrecarga
        // deprecated de `createServerClient` (get/set/remove) vem ANTES da
        // atual (getAll/setAll) em @supabase/ssr, então o TypeScript tipa
        // `cookiesToSet` contextualmente pela primeira, que não tem `setAll`.
        setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
          try {
            cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
          } catch {
            // Chamado de um Server Component (não pode escrever cookies) — o
            // middleware já cuida do refresh de sessão nesse caso. Seguro ignorar.
          }
        },
      },
    },
  );
}
