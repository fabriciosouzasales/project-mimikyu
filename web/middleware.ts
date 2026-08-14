import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Refresh de sessão (cookies de Auth) a cada requisição — plumbing obrigatória
 * do @supabase/ssr para o App Router, independente de proteção de rotas.
 *
 * IMPORTANTE: isto NÃO é controle de acesso, só mantém a sessão válida
 * atualizada. Guardas de rota por papel (`role`) ficam em
 * `requireCatalogoAdmin()` (Server Components), não aqui.
 *
 * Lógica trazida para dentro de `middleware.ts` (2026-08-14, hotfix de
 * incidente de produção — ver `docs/log.md`) — antes vivia em
 * `web/lib/supabase/middleware.ts` (`updateSession()`), importada por alias
 * `@/lib/supabase/middleware`. O empacotamento de Node Middleware da Vercel
 * não resolveu esse import de arquivo local de forma confiável em nenhuma
 * das duas tentativas anteriores (alias `@/` tratado como pacote npm
 * inexistente; depois import relativo com extensão `.js` quebrando a
 * resolução do Webpack) — inlinar elimina inteiramente a resolução de
 * módulo local nesse artefato: `middleware.ts` passa a importar só pacotes
 * npm (`@supabase/ssr`, `next/server`), nunca arquivos do projeto.
 * `web/lib/supabase/middleware.ts` permanece no repositório, sem consumidor
 * por ora — não removido nesta rodada.
 */
export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        // Anotação explícita necessária (mesma nota original de
        // lib/supabase/middleware.ts): `createServerClient` tem uma
        // sobrecarga deprecated (get/set/remove) declarada ANTES da
        // sobrecarga atual (getAll/setAll) em
        // node_modules/@supabase/ssr/dist/main/createServerClient.d.ts — o
        // TypeScript tipa contextualmente um argumento de função
        // sobrecarregada pela PRIMEIRA sobrecarga compatível, que não
        // declara `setAll`, então `cookiesToSet` cai para `any` implícito
        // sem a anotação abaixo.
        setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
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

export const config = {
  runtime: "nodejs",
  matcher: [
    /*
     * Roda em todas as rotas exceto assets estáticos e imagens —
     * mesmo padrão recomendado pela documentação do @supabase/ssr.
     */
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
