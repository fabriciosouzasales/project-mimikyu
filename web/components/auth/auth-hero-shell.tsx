import type { ReactNode } from "react";
import { BrandLogo } from "@/components/brand-logo";
import { ThemeToggle } from "@/components/theme-toggle";
import { AuthHero } from "@/components/auth/auth-hero";
import { cn } from "@/lib/utils";
import styles from "@/components/auth/auth-tokens.module.css";

/**
 * Casca visual real da Auth Experience — direção "cartas reais" (protótipos
 * v3 → v4, aprovados 2026-08-15; implementação original em rodada anterior,
 * ver docs/log.md). Escopada pela classe local `styles.scope` (tokens em
 * `auth-tokens.module.css`, isolados de `app/globals.css`).
 *
 * Rodada de fechamento da Auth Experience V1 (2026-08-16, ver docs/log.md):
 * Login, Cadastro, Recuperar Senha e Atualizar Senha agora compartilham
 * exatamente esta casca — `LegacyAuthShell` ficou órfã e foi removida. As
 * 4 rotas usam o mesmo hero (mesmo headline/subheadline fixos em
 * `AuthHero`, mesmas 3 cartas, mesma flutuação, mesmo slot vazio/glow), só
 * o conteúdo do painel direito (`children`) muda por rota.
 *
 * Três tiers responsivos, não dois — mobile e tablet são composições
 * distintas entre si e do desktop (ver `auth-hero.tsx`), não o mesmo layout
 * comprimido. `BrandLogo`/`ThemeToggle` ficam sempre no lado do formulário,
 * nunca sobre o hero: o hero é propositalmente escuro nos dois temas do
 * site, e `BrandLogo` escolhe sua variante pelo tema REAL (`resolvedTheme`),
 * não pelo fundo local — colocá-la sobre o hero quebraria o contraste no
 * tema claro (logo escura sobre fundo já escuro).
 *
 * Hero estável mesmo com painéis de altura diferente (nova exigência desta
 * rodada — Cadastro é visivelmente mais alto que Login/Recuperar/
 * Atualizar): no desktop (`lg:`) a casca inteira é travada em `lg:h-dvh`
 * (não apenas `min-h-dvh`) e a coluna direita ganha `lg:overflow-hidden`
 * com o próprio `main` rolando internamente (`lg:overflow-y-auto`) — o
 * hero, à esquerda, nunca herda a altura do formulário. O conteúdo do
 * painel é centralizado com `margin: auto` no wrapper interno (não
 * `items-center`/`justify-center` no pai) porque `margin: auto` centraliza
 * quando cabe e rola a partir do topo, sem cortar o início do conteúdo,
 * quando não cabe — `items-center` sozinho tem esse bug conhecido de
 * flexbox com overflow. Abaixo de `lg:` (tablet/mobile) o comportamento
 * anterior foi mantido sem alteração: `min-h-dvh` + rolagem natural da
 * página inteira (já era o certo para essas larguras, ver `auth-hero.tsx`).
 */
export function AuthHeroShell({ children }: { children: ReactNode }) {
  return (
    <div className={cn("min-h-dvh bg-[hsl(var(--auth-page))] lg:h-dvh lg:overflow-hidden", styles.scope)}>
      <div className="grid min-h-dvh lg:h-full lg:grid-cols-[3fr_2fr]">
        <div className="min-h-[260px] sm:min-h-[320px] lg:h-full">
          <AuthHero />
        </div>

        <div className="flex flex-col lg:h-full lg:overflow-hidden">
          <header className="flex h-16 shrink-0 items-center justify-between border-b border-[hsl(var(--auth-form-line))] px-5 lg:h-[88px] lg:px-11">
            <BrandLogo className="h-6 w-auto lg:h-[30px]" />
            <ThemeToggle />
          </header>
          <main className="flex flex-1 p-5 pb-10 lg:overflow-y-auto lg:p-11">
            <div className="m-auto w-full max-w-[352px]">{children}</div>
          </main>
        </div>
      </div>
    </div>
  );
}
