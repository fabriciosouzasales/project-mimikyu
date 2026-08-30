import { ME2_CARDS, type RealCardData } from "./mock-data";
import { getCardSetInfoMock } from "./card-detail-mock";

/**
 * BINDER-ADD-REPLACE-CARD-01 (2026-08-29) — dados mockados do Card Picker
 * (`components/experimental/binder-nav-01/card-picker-modal.tsx`). Pedido de
 * Fabrício: "usar mock estruturado coerente com o domínio; não inventar novo
 * modelo; documentar exatamente qual parte ainda está mockada."
 *
 * Reaproveita, em vez de duplicar:
 *  - `ME2_CARDS` (`mock-data.ts`) — o MESMO pool de 18 cartas reais que já
 *    preenche os 224 bolsos do Binder.
 *  - `getCardSetInfoMock` (`card-detail-mock.ts`) — a MESMA lógica de
 *    Set/número/variant já usada no Card Detail, para que a informação
 *    mostrada no Picker seja consistente com a que aparece depois de
 *    selecionar a carta e abrir o Card Detail (mesmo `card.id` → mesmo
 *    resultado nos dois lugares).
 *
 * O QUE ESTE ARQUIVO NÃO FAZ (fronteira explícita do mock): não modela
 * `Card Variant` nem `Inventory Item` reais (`docs/domain-modeling/
 * collections/logical-model.md`, LDM-19/LDM-24) — não há leitura de banco,
 * não há Card Variant de verdade por trás de `variantLabel`. O único
 * conceito novo aqui é `copiesAvailable`, um número mock determinístico
 * (nunca `Math.random()`) que representa, só para a experiência do Picker,
 * "quantas cópias dessa carta ainda não foram alocadas a este Binder" — um
 * conceito PRÓXIMO do real (`Inventory Item` não alocado a nenhuma
 * `Collection`/slot), mas calculado por hash do `card.id`, não por uma
 * contagem real de Inventory. Isso é intencional: a direção conceitual já
 * aprovada ("Collection apenas aloca Inventory Items; não criar Collection
 * Item paralelo") pede que o picker DEIXE CLARO quando existe cópia
 * disponível — este número é só o suficiente para demonstrar essa
 * affordance visualmente. Ligar isso a um `Inventory` real de verdade é
 * trabalho de integração de backend, fora de escopo desta rodada.
 *
 * `copiesAvailable === 0` desabilita a seleção da carta no Picker (o botão
 * fica com `disabled`) — decisão deliberada, não uma omissão: reflete a
 * regra de domínio ("só é possível alocar um Inventory Item que existe") já
 * no nível da UI mockada, mesmo sem Inventory real por trás. Como as MESMAS
 * 18 cartas já preenchem repetidamente os 224 bolsos do Binder inteiro, é
 * plausível que boas partes delas já estejam "todas alocadas" (0
 * disponíveis) e só algumas tenham cópia sobrando — o hash foi calibrado
 * (`% 4`) para refletir essa mistura, não para ser uniforme.
 */

export interface CardPickerEntry {
  card: RealCardData;
  setCode: string;
  setName: string;
  number: string;
  variantLabel?: string;
  /** Mock — ver doc-comment do arquivo. NÃO é uma contagem real de Inventory. */
  copiesAvailable: number;
}

// Hash local, deliberadamente separado do `hashCardId` privado de
// `card-detail-mock.ts` — evita acoplar este arquivo a um símbolo não
// exportado de outro mock só para um número que representa um conceito
// diferente (disponibilidade no Picker, não "cópias possuídas no acervo").
function localHash(id: string): number {
  let hash = 0;
  for (let i = 0; i < id.length; i++) {
    hash = (Math.imul(hash, 33) + id.charCodeAt(i)) >>> 0;
  }
  return hash;
}

function getCopiesAvailableMock(cardId: string): number {
  return localHash(cardId) % 4; // 0..3 — ~1/4 das cartas ficam "sem cópia disponível".
}

/** Todas as cartas do pool ME2, com Set/número/variant/disponibilidade resolvidos uma única vez. */
export const CARD_PICKER_ENTRIES: CardPickerEntry[] = ME2_CARDS.map((card) => {
  const setInfo = getCardSetInfoMock(card);
  return {
    card,
    setCode: setInfo.setCode,
    setName: setInfo.setName,
    number: setInfo.number,
    variantLabel: setInfo.variantLabel,
    copiesAvailable: getCopiesAvailableMock(card.id),
  };
});

/**
 * Busca local simples (substring, case-insensitive, sem acento-fold) sobre
 * nome/número/Set/variant — ESCOPO V1 explícito do pedido ("nome da carta;
 * número; Set/Card Set; variant/printing quando necessário"), sem filtros
 * avançados. `cmdk` (motor de busca fuzzy com teclado) não está instalado
 * neste projeto (`web/package.json` não lista a dependência, apesar de a
 * curadoria `mmkyu-frontend-experience` recomendá-lo como candidato — ver
 * relatório desta rodada) — por pedido explícito de Fabrício, nenhuma
 * dependência nova foi instalada automaticamente; esta função substitui o
 * motor fuzzy por um filtro simples, suficiente para um pool de 18 cartas.
 */
export function searchCardPickerEntries(entries: CardPickerEntry[], query: string): CardPickerEntry[] {
  const term = query.trim().toLowerCase();
  if (!term) return entries;
  return entries.filter((entry) => {
    return (
      entry.card.name.toLowerCase().includes(term) ||
      entry.number.toLowerCase().includes(term) ||
      entry.setCode.toLowerCase().includes(term) ||
      entry.setName.toLowerCase().includes(term) ||
      (entry.variantLabel?.toLowerCase().includes(term) ?? false)
    );
  });
}
