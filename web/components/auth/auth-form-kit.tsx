import Link from "next/link";
import { Button } from "@/components/ui/button";
import panelStyles from "@/components/auth/auth-panel.module.css";

/**
 * Peças visuais compartilhadas do formulário customer-facing da Auth
 * Experience — extraídas de `login-form.tsx` (fechamento da Auth
 * Experience V1, 2026-08-16, ver docs/log.md) para que Cadastro/Recuperar/
 * Atualizar Senha usem exatamente a mesma casca sem duplicar CSS/JSX. O
 * tratamento visual aprovado do Login (Input/Label/CTA/link, radius,
 * contraste, estados de foco, claro/escuro) é a referência — este arquivo
 * é só a extração mecânica dele, sem nenhuma mudança de valor/token. Nada
 * aqui foi redesenhado; é a mesma implementação que já existia inline em
 * `login-form.tsx`, só reembalada para reuso.
 *
 * `authInputClassName` (2026-08-16, consolidação de formulários — Login
 * vira Design System global): encolhido para só o que ainda É diferente do
 * `Input` compartilhado. Superfície/borda/radius/placeholder/foco foram
 * promovidos para `components/ui/input.tsx` via os tokens `--control-*`
 * (`app/globals.css`) — como `--auth-form-surface`/`--auth-form-line`/
 * `--auth-form-ink-muted`/`--auth-radius-control` agora só apontam
 * (`var(--control-*)`) para os mesmos valores, remover essas classes daqui
 * não muda um pixel: `Input` já renderiza exatamente isso por padrão. Só
 * sobra o que É uma diferença legítima do formulário hero: altura `h-11`
 * (backoffice usa `h-9` — instrução explícita de não igualar dimensões) e a
 * sombra interna sutilíssima (0.02 de opacidade) do polish visual do Login.
 */

export const authLabelClassName = "text-[12.5px] font-medium tracking-[0.01em] text-[hsl(var(--auth-form-ink))]";

export const authInputClassName = "h-11 shadow-[inset_0_1px_1px_hsl(var(--auth-form-ink)/0.02)]";

export function AuthPanelHeading({ title, description }: { title: string; description: string }) {
  return (
    <div className="mb-7 space-y-1.5">
      <h2 className="text-[22px] font-semibold tracking-[-0.01em] text-[hsl(var(--auth-form-ink))]">{title}</h2>
      <p className="text-[13px] leading-relaxed text-[hsl(var(--auth-form-ink-muted))]">{description}</p>
    </div>
  );
}

export function AuthFooterLink({ prompt, href, label }: { prompt?: string; href: string; label: string }) {
  return (
    <p className="mt-7 text-center text-[13px] text-[hsl(var(--auth-form-ink-muted))]">
      {prompt ? `${prompt} ` : null}
      <Link href={href} className="font-medium text-[hsl(var(--auth-accent-ink))] hover:underline">
        {label}
      </Link>
    </p>
  );
}

export function AuthSubmitButton({
  pending,
  pendingLabel,
  label,
}: {
  pending: boolean;
  pendingLabel: string;
  label: string;
}) {
  return (
    <Button
      type="submit"
      disabled={pending}
      className={`${panelStyles.cta} h-[46px] w-full rounded-[var(--auth-radius-control)] border-transparent text-sm font-semibold`}
    >
      {pending ? pendingLabel : label}
    </Button>
  );
}

/**
 * Mesmo tratamento visual de `AuthSubmitButton` (CTA em gradiente dourado,
 * `auth-panel.module.css`), só que como link de navegação (`next/link`) em
 * vez de `<button type="submit">` — para ações de "voltar"/"continuar" que
 * não submetem formulário.
 */
export function AuthLinkButton({ href, label }: { href: string; label: string }) {
  return (
    <Link
      href={href}
      className={`${panelStyles.cta} flex h-[46px] w-full items-center justify-center rounded-[var(--auth-radius-control)] border-transparent text-sm font-semibold`}
    >
      {label}
    </Link>
  );
}
