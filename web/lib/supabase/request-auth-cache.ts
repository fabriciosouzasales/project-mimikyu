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
 * Isto NÃO reduz nem enfraquece nenhuma validação — dentro do escopo de uma
 * requisição já autenticada, cada chamador (guard/AppShell/Header) continua
 * efetivamente "revalidando" o mesmo dado, só deixa de pagar o custo de rede
 * mais de uma vez por ele.
 *
 * CORREÇÃO (2026-08-23, diagnóstico P0 de performance de /pricing): o
 * parágrafo original desta nota dizia que `web/middleware.ts` continuava
 * fazendo refresh de sessão a cada navegação — isso deixou de ser verdade em
 * 2026-08-14 (incidente de produção na Vercel, `MIDDLEWARE_INVOCATION_FAILED`,
 * ver `docs/log.md`). `web/middleware.ts` foi REMOVIDO; `updateSession()` em
 * `lib/supabase/middleware.ts` ficou órfã, sem nenhum consumidor — o refresh
 * de sessão hoje é feito no browser por `components/auth/session-refresher.tsx`.
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

/**
 * `getCachedUserProfile()` (Fase 2 do diagnóstico P0 de performance,
 * 2026-08-23) — mesma disciplina de `getCachedUser`/`getCachedIsAdmin`
 * acima, agora estendida à leitura de `user_profile` que antes vivia só
 * dentro de `Header` (own `createClient()` + query própria, fora deste
 * cache — achado da instrumentação: 21% do tempo de `/pricing`, e em
 * `/catalogo` disparava DUAS vezes por requisição, uma pelo `loading.tsx`
 * da rota — que também renderiza `AppShell`/`Header` reais como esqueleto,
 * ver `app/catalogo/loading.tsx` — e outra pela `page.tsx` real; ambas
 * dentro da MESMA requisição HTTP, então o mesmo `cache()` que já deduplica
 * `getCachedUser`/`getCachedIsAdmin` entre múltiplos renders também deduplica
 * esta).
 *
 * Depende de `getCachedUser()` (reaproveita a mesma promise memoizada, sem
 * custo de rede extra) e só then faz a query real de `user_profile` — por
 * isso os guards (`requirePricingAdmin`/`requireCatalogoAdmin`) disparam
 * esta função (sem aguardar) logo depois de resolver `user`, ANTES das
 * leituras específicas da página: a promise memoizada já fica "em voo"
 * durante o `Promise.all` das RPCs da página, em vez de só começar depois
 * que `AppShell`/`Header` renderizam (o que antes forçava uma 3ª fase
 * sequencial, sem sobreposição com nada). Não lança exceção em uso normal
 * (mesmo padrão de `getCachedUser`/`getCachedIsAdmin`: erros do Supabase
 * voltam como `{ data: null }`, nunca como rejection).
 */
export const getCachedUserProfile = cache(async () => {
  const {
    data: { user },
  } = await getCachedUser();

  if (!user) {
    return { profile: null, avatarUrl: null as string | null };
  }

  const supabase = await createClient();
  const { data: profile } = await supabase
    .from("user_profile")
    .select("username, display_name, avatar_path")
    .eq("id", user.id)
    .maybeSingle();

  let avatarUrl: string | null = null;
  if (profile?.avatar_path) {
    avatarUrl = supabase.storage.from("avatars").getPublicUrl(profile.avatar_path).data.publicUrl;
  }

  return { profile, avatarUrl };
});
