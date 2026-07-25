import { createServerClient } from "@supabase/ssr";
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
        setAll(cookiesToSet) {
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
