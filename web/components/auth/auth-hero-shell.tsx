import type { ReactNode } from "react";
import { BrandLogo } from "@/components/brand-logo";
import { ThemeToggle } from "@/components/theme-toggle";
import { AuthHero } from "@/components/auth/auth-hero";
import { cn } from "@/lib/utils";
import styles from "@/components/auth/auth-tokens.module.css";

/**
 * Casca visual real da Auth Experience — direção "cartas reais" (protótipos
 * v3 → v4, aprovados 2026-08-15; implementação nesta rodada, ver
 * docs/log.md). Escopada pela classe local `styles.scope` (tokens em
 * `auth-tokens.module.css`, isolados de `app/globals.css`).
 *
 * Login é o único consumidor real por enquanto. Cadastro/Recuperar/
 * Atualizar Senha permanecem na casca legada (`LegacyAuthShell`) — este
 * componente foi desenhado para que essas 3 telas possam migrar depois sem
 * reconstrução arquitetural (mesmo `.scope`/tokens, mesmo padrão de
 * `AuthHero`+cabeçalho+`main` centralizado), mas essa migração NÃO faz
 * parte deste incremento.
 *
 * Três tiers responsivos, não dois — mobile e tablet são composições
 * distintas entre si e do desktop (ver `auth-hero.tsx`), não o mesmo layout
 * comprimido. `BrandLogo`/`ThemeToggle` ficam sempre no lado do formulário,
 * nunca sobre o hero: o hero é propositalmente escuro nos dois temas do
 * site, e `BrandLogo` escolhe sua variante pelo tema REAL (`resolvedTheme`),
 * não pelo fundo local — colocá-la sobre o hero quebraria o contraste no
 * tema claro (logo escura sobre fundo já escuro).
 *
 * Rodada de polish final (2026-08-16, ver docs/log.md): Fraunces removida
 * (headline passou a usar Inter, `var(--font-sans)` já global — nenhum
 * carregamento de fonte específico deste componente sobrou para remover
 * depois). `headline`/`subheadline` deixaram de ser props — a copy é
 * definitiva agora, fixada dentro de `AuthHero`; o andaime temporário de
 * comparação (`auth-copy-variants.ts`, `?copy=`) foi removido.
 *
 * `min-h-*` (não `h-*`) no contêiner do hero abaixo de `lg:` — a nova copy
 * (bem mais longa que a anterior) pode precisar de mais altura que o piso
 * estético original; `min-h` cresce com o conteúdo em vez de arriscar
 * cortar texto num contêiner de altura fixa. Só o desktop (`lg:h-auto`,
 * inalterado) segue preenchendo a altura real do grid — ali a composição é
 * a mesma do v4, sem risco de overflow.
 */
export function AuthHeroShell({ children }: { children: ReactNode }) {
  return (
    <div className={cn("min-h-dvh bg-[hsl(var(--auth-page))]", styles.scope)}>
      <div className="grid min-h-dvh lg:grid-cols-[3fr_2fr]">
        <div className="min-h-[260px] sm:min-h-[320px] lg:h-auto">
          <AuthHero />
        </div>

        <div className="flex flex-col">
          <header className="flex h-16 shrink-0 items-center justify-between border-b border-[hsl(var(--auth-form-line))] px-5 lg:h-[88px] lg:px-11">
            <BrandLogo className="h-6 w-auto lg:h-[30px]" />
            <ThemeToggle />
          </header>
          <main className="flex flex-1 items-center justify-center p-5 pb-10 lg:p-11">
            <div className="w-full max-w-[352px]">{children}</div>
          </main>
        </div>
      </div>
    </div>
  );
}
