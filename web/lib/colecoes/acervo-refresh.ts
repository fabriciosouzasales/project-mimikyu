/**
 * PERFORMANCE INCIDENT-01, E1 (C2a) — quando o Meu acervo ainda precisa de `router.refresh()`
 * depois de uma mutação.
 *
 * Regra do Next.js 15.5 (verificada no código da versão instalada, `server/app-render/action-handler`
 * + `web/spec-extension/revalidate`): uma Server Action que chama `revalidatePath` — QUALQUER caminho —
 * devolve, na mesma resposta, a rota atual renderizada de novo, e o roteador do cliente aplica essa
 * árvore antes de a chamada da ação terminar. Um `router.refresh()` logo depois pede uma SEGUNDA
 * renderização completa da página (≈14 leituras ao banco com o detalhe aberto). Medido no LIVE em
 * 2026-11-07: 2 renderizações e 28 leituras nos 2,5 s seguintes a cada mutação.
 *
 * Por isso o cliente só pede `refresh` quando a ação comprovadamente NÃO revalidou:
 * - mover (5024): a ação revalida em sucesso, `unknown`, `plan_changed` e `storage_gone`
 *   (`moveMyCopies`); `unresolved` não revalida. `unknown` também nasce no cliente quando a chamada
 *   cai no meio (a resposta pode não ter chegado) — por isso continua pedindo refresh;
 * - prévia de mover (`previewMyCopiesMove`) nunca revalida — `storage_gone` continua com refresh
 *   (decidido no próprio painel);
 * - cadastro pelo painel "Adicionar": no Meu acervo (sem destino) a ação já revalida; nos outros
 *   lugares que reutilizam o painel (coleção, fichário com o passo do bolso) o comportamento fica
 *   como estava — fora do escopo medido.
 *
 * Os demais fluxos do acervo (quantidade, lixeira, localização) já revalidam em todos os
 * desfechos que antes pediam refresh — ver o teste de guarda em `acervo-refresh.test.ts`.
 */

/** Desfechos de `moveMyCopies` que a própria ação revalida (espelho de `app/colecoes/acervo/actions.ts`). */
export const MOVE_CONFIRM_REVALIDATED_REASONS = ["unknown", "plan_changed", "storage_gone"] as const;

/** Depois de confirmar uma movimentação: `true` só quando a resposta da ação não trouxe a rota nova. */
export function moveConfirmNeedsClientRefresh(result: { ok: true } | { ok: false; reason: string }): boolean {
  if (result.ok) return false;
  // `unknown`: pode ter vindo do servidor (revalidado) ou de uma falha de rede no cliente (sem
  // resposta) — sem como distinguir aqui, o refresh fica.
  return result.reason === "unresolved" || result.reason === "unknown";
}

/**
 * Depois de um cadastro bem-sucedido pelo painel "Adicionar": no Meu acervo (sem destino) a ação já
 * devolve a rota atualizada; com destino (coleção, fichário) o refresh permanece como antes.
 */
export function addCommitNeedsClientRefresh(input: { hasTarget: boolean }): boolean {
  return input.hasTarget;
}

/**
 * INCIDENT-01 E0/E1 VALIDATION-01 — estado provisório sem depender da ordem de chegada.
 *
 * Sem o `router.refresh()` extra, a leitura nova do servidor chega na resposta da própria ação e
 * pode ser aplicada antes ou depois do estado provisório gravado no cliente. As duas regras abaixo
 * fazem a interface estabilizar no estado confirmado pelo servidor em qualquer ordem
 * (`activeProvisional` para a localização, `quantityToSyncAfterSave` para a quantidade).
 */

/**
 * Provisório de localização: vale só enquanto a leitura exibida for a mesma de quando a gravação
 * começou (`basis`, comparada por identidade — cada resposta do servidor é um objeto novo). Chegou
 * outra leitura, antes ou depois de o provisório ser gravado → o servidor manda.
 */
export function activeProvisional<P extends { basis: unknown }>(patch: P | null, current: unknown): P | null {
  return patch !== null && patch.basis === current ? patch : null;
}

/**
 * Quantidade: ao terminar o envio, o número exibido volta ao total do servidor se ele mudou durante
 * o envio (a resposta da ação pode chegar enquanto o envio ainda está em andamento, quando o efeito
 * de sincronização não age). `null` = nada a sincronizar (ex.: falha sem alteração — a escolha do
 * colecionador fica para nova tentativa com a mesma chave de idempotência).
 */
export function quantityToSyncAfterSave(totalAtStart: number, latestTotal: number): number | null {
  return latestTotal !== totalAtStart ? latestTotal : null;
}
