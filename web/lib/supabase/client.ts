import { createBrowserClient } from "@supabase/ssr";

/**
 * Cliente Supabase para uso em Client Components.
 * Usa a publishable/anon key (segura para o navegador) — a autorização real
 * é feita por RLS no Postgres, não por este cliente (ver ADR-019/decisão
 * "Data API + RLS" registrada na fundação do frontend).
 */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
