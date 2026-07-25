import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Refresh de sessão (cookies de Auth) a cada requisição — plumbing obrigatória
 * do @supabase/ssr para o App Router, independente de proteção de rotas.
 *
 * IMPORTANTE (registrado para a Etapa 3): isto NÃO é controle de acesso.
 * Isto só mantém a sessão válida atualizada. Guardas de rota por papel
 * (`role`) serão adicionadas explicitamente na Etapa 3, sobre esta mesma base.
 */
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
        },
      },
    },
  );

  // Necessário revalidar o usuário (não só ler o cookie) para o refresh funcionar.
  await supabase.auth.getUser();

  return response;
}
