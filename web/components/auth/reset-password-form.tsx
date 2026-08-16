"use client";

import { useActionState } from "react";
import { requestPasswordReset, type AuthActionState } from "@/app/(auth)/actions";
import { Alert } from "@/components/ui/alert";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  AuthFooterLink,
  AuthLinkButton,
  AuthPanelHeading,
  AuthSubmitButton,
  authInputClassName,
  authLabelClassName,
} from "@/components/auth/auth-form-kit";

const initialState: AuthActionState = { error: null };

/**
 * Painel de Recuperar Senha — migrado de
 * `app/(auth)/recuperar-senha/page.tsx` (fechamento da Auth Experience V1,
 * 2026-08-16, ver docs/log.md), mesma linguagem visual do Login. Lógica
 * (`requestPasswordReset`, pending/erro/sucesso) preservada byte a byte —
 * `app/(auth)/actions.ts` intocado.
 *
 * Correção (2026-08-16, mesmo dia): a primeira versão desta rodada mantinha
 * o MESMO heading ("Recupere o acesso à sua coleção." / "Informe o e-mail
 * da sua conta...") visível mesmo depois do envio, com a confirmação
 * aparecendo como um Alert genérico logo abaixo — texto contraditório
 * (pede o e-mail de novo enquanto já confirma o envio) e fora da linguagem
 * visual premium aprovada no Login. Agora `state.success` troca o heading
 * inteiro (não só o corpo abaixo dele) para a copy de confirmação, com um
 * indicador de sucesso discreto (check dourado em círculo, sem verde
 * genérico, sem Card/Alert/modal/glassmorphism) — o hero à esquerda nunca
 * muda; só o conteúdo do painel direito transiciona de formulário para
 * confirmação, no mesmo lugar.
 *
 * Ajuste (mesmo dia): no estado de sucesso, "Voltar para entrar" virou
 * `AuthLinkButton` — mesmo tratamento de CTA do botão "Entrar" da tela de
 * Login (`auth-panel.module.css`), não mais um link de texto — já que ali é
 * a única ação disponível. No estado de formulário o link permanece texto
 * (`AuthFooterLink`), por já haver um CTA primário ("Enviar link de
 * recuperação") na mesma tela.
 */
export function ResetPasswordForm() {
  const [state, formAction, pending] = useActionState(requestPasswordReset, initialState);

  if (state.success) {
    return (
      <div>
        <SuccessCheck />
        <AuthPanelHeading
          title="Verifique seu e-mail"
          description="Enviamos as instruções para redefinir sua senha. Se existir uma conta associada ao endereço informado, você receberá o link em alguns instantes."
        />
        <div className="mt-7">
          <AuthLinkButton href="/login" label="Voltar para entrar" />
        </div>
      </div>
    );
  }

  return (
    <div>
      <AuthPanelHeading
        title="Recupere o acesso à sua coleção."
        description="Informe o e-mail da sua conta. Enviaremos um link para você criar uma nova senha e continuar de onde parou."
      />

      <form action={formAction} className="space-y-5" noValidate>
        {state.error && <Alert variant="destructive">{state.error}</Alert>}

        <div className="space-y-1.5">
          <Label htmlFor="email" className={authLabelClassName}>
            E-mail
          </Label>
          <Input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            required
            invalid={!!state.error}
            className={authInputClassName}
          />
        </div>

        <AuthSubmitButton pending={pending} pendingLabel="Enviando…" label="Enviar link de recuperação" />
      </form>

      <AuthFooterLink href="/login" label="Voltar para entrar" />
    </div>
  );
}

/**
 * Indicador de sucesso discreto — círculo com borda/preenchimento sutis em
 * `--auth-accent`. Confirmação visual, não protagonista: sem verde
 * genérico, sem ilustração.
 *
 * Ajuste (mesmo dia): o check usava `--auth-accent-bright` (dourado claro,
 * fixo nos dois temas) — no modo claro ficava com contraste baixo demais
 * sobre o círculo âmbar claro, quase ilegível. Trocado para
 * `--auth-form-ink` (mesma tinta de texto do painel, já correta nos dois
 * temas: preto no claro, quase branco no escuro) — o círculo âmbar
 * continua carregando a identidade dourada, o traço do check só precisa
 * ser legível.
 */
function SuccessCheck() {
  return (
    <div
      className="mb-5 flex h-9 w-9 items-center justify-center rounded-full border border-[hsl(var(--auth-accent)/0.35)] bg-[hsl(var(--auth-accent)/0.1)]"
      aria-hidden="true"
    >
      <svg width="15" height="15" viewBox="0 0 16 16" fill="none">
        <path
          d="M3 8.4L6.3 11.7L13 4.3"
          stroke="hsl(var(--auth-form-ink))"
          strokeWidth="1.6"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </div>
  );
}
