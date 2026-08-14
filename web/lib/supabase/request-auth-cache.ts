import { cache } from "react";
import { createClient } from "@/lib/supabase/server";

/**
 * Deduplicação de `auth.getUser()`/`rpc("is_admin")` dentro da MESMA
 * requisição (Etapa de performance, Incremento 1 — 2026-08-14, achado #0/#1
 * da auditoria de performance frontend).
 *
 * Antes desta mudança, `requireCatalogoAdmin()` (catalogo-guard.tsx),
 * `AppShell` e `Header` cada um criava seu próprio client via
 * `createClient()` e refazia a MESMA chamada de rede (`getUser()` 2x,
 * `is_admin()` 2x) dentro de uma única renderização, sem nenhum ganho de
 * informação — só custo de rede repetido, direto na waterfall de TTFB.
 *
 * `cache()` do React memoiza por (função + argumentos) dentro do escopo de
 * UMA requisição de servidor (App Router) — funções sem argumento têm uma
 * única entrada de cache por requisição; a partir da segunda chamada, o
 * mesmo Promise já resolvido é reaproveitado, sem round-trip novo.
 *
 * Isto NÃO reduz nem enfraquece nenhuma validação: `middleware.ts` continua
 * chamando `auth.getUser()` a cada navegação, exatamente como hoje (refresh
 * de sessão, escopo de requisição HTTP diferente deste cache — que só existe
 * dentro do processamento de UMA requisição já autenticada). Dentro dela,
 * cada chamador (guard/AppShell/Header) continua efetivamente "revalidando"
 * o mesmo dado — só deixa de pagar o custo de rede mais de uma vez por ele.
 *
 * Escopo deliberadamente restrito aos dois pontos citados pela auditoria
 * (getUser/is_admin repetidos entre requireCatalogoAdmin, AppShell e
 * Header). Não estende a outros chamadores de `createClient()`
 * (`app/usuarios/page.tsx`, `app/perfil/page.tsx`, uploaders, Server
 * Actions, etc.) — cada um continua criando seu próprio client e revalidando
 * normalmente, sem mudança de comportamento. Ver auditoria de performance
 * (2026-08-14) para o racional completo de por que esta foi a opção
 * escolhida em vez de propagar `user`/`isAdmin` via props (exigiria alterar
 * a assinatura de `AppShell`/`Header` e todo `page.tsx` que os chama — mais
 * de 20 arquivos, incluindo rotas que não passam por `requireCatalogoAdmin`).
 */

export const getCachedUser = cache(async () => {
  const supabase = await createClient();
  return supabase.auth.getUser();
});

export const getCachedIsAdmin = cache(async () => {
  const supabase = await createClient();
  return supabase.rpc("is_admin");
});
