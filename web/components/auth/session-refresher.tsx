"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

/**
 * Mantém o auto-refresh de sessão do Supabase ativo durante o uso da
 * aplicação — mitigação de ESTABILIZAÇÃO (2026-08-14, ver `docs/log.md`)
 * para o refresh de sessão que antes era feito por `middleware.ts`,
 * removido nesta mesma rodada após incidente de produção na Vercel: o
 * bundle Edge do middleware falhava com `ReferenceError: __dirname is not
 * defined`, causa estrutural do próprio `next/server` (vercel/next.js#53968),
 * sem correção disponível em nenhuma versão 15.x.
 *
 * `createClient()` (lib/supabase/client.ts → `createBrowserClient` do
 * @supabase/ssr) já vem, por padrão em ambiente de navegador,
 * com `autoRefreshToken`/`persistSession`/`detectSessionInUrl` ativados
 * (@supabase/ssr/dist/main/createBrowserClient.js). Ao ser instanciado e
 * permanecer vivo, o cliente inicia sozinho o ciclo de renovação de token
 * (GoTrueClient — auto-inicializa no construtor, registra o listener de
 * `visibilitychange` e dispara `_startAutoRefresh()` com a aba em foco, sem
 * nenhuma chamada manual necessária aqui) e persiste o token renovado via
 * `document.cookie` — escrita que Server Components não conseguem fazer
 * (restrição do App Router), mas que o navegador sempre permite.
 *
 * Instância única por montagem (`useState` com inicializador preguiçoso): o
 * layout raiz permanece montado durante toda a navegação client-side do App
 * Router, então este componente também permanece montado — não recria o
 * client, e portanto não duplica o listener de `visibilitychange`, a cada
 * troca de rota. Não renderiza nada; existe só para manter o client vivo.
 *
 * DÍVIDA TÉCNICA (registrada em `docs/log.md`): restaurar o refresh de
 * sessão via Proxy/Middleware (recomendação oficial do Supabase para SSR,
 * `@supabase/ssr`) assim que a incompatibilidade entre o Edge Runtime da
 * Vercel e o bundle do `next/server` for resolvida de forma definitiva
 * (upgrade controlado de stack) — este componente é a ponte temporária, não
 * a arquitetura pretendida.
 */
export function SessionRefresher() {
  const [supabase] = useState(() => createClient());

  useEffect(() => {
    return () => {
      supabase.auth.stopAutoRefresh();
    };
  }, [supabase]);

  return null;
}
