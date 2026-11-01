# Lista de desejos (Wishlist) — Contrato funcional de produto (V1-11, W0)

| Campo | Valor |
|---|---|
| **Documento** | Contrato funcional de produto da Lista de desejos (Wishlist) — V1-11 |
| **Arquivo** | `docs/domain-modeling/collections/wishlist-product-contract.md` |
| **Versão** | 1.1 |
| **Status** | **APROVADO (W0)** — decisões D1–D9 do proprietário (2026-10-31, `V1-11 W0 — PRODUCT CONTRACT CONSOLIDATION-02`), sobre o diagnóstico `V1-11 WISHLIST PRODUCT & CONTRACT DISCOVERY-01`. **Sem modelo físico**: nenhum SQL, migration ou código existe para a Wishlist; a fundação física é a W1, ainda não iniciada. |
| **Autoridade** | Em domínio prevalecem `concept-decisions.md` **C-91–C-102** (inalteradas) e **C-210–C-219** (novas, W0) e `logical-model.md` **LDM-79–LDM-90** (inalteradas) e **LDM-204–LDM-208**. Este documento é a leitura funcional consolidada; em caso de divergência, os C-*/LDM-* vencem. Nomenclatura: North Star **N27**. |
| **Fora de escopo** | SQL, migrations, telas, Conexão Inteligente (CI-N1/CI-N2), marketplace, pagamentos, quantidade, prioridade, preço-alvo, alertas, condição e graduação. |
| **Documentos relacionados** | `concept-decisions.md`, `logical-model.md`, `north-star-2026-10-16.md`, `architecture/ubiquitous-language.md`, `docs/ROADMAP.md` (V1-11), `docs/05d-colecoes-e-usuarios.md`, `docs/05f-pricing.md` (V1-09), `COLLECTION-FUNCTIONAL-COVERAGE-AUDIT-01.md` (WF-02/WF-03) |

---

## 1. Definição

A **Lista de desejos** (termo técnico: Wishlist) é a intenção pessoal e privada de um usuário de adquirir uma **variante específica** de uma carta, com preferência opcional de idioma (C-91, C-92). Não é a lista de faltantes de uma coleção (C-94), não é Favoritos (C-97) e não pertence a coleção, acervo, fichário ou exemplar (C-95, C-102).

`Favoritos → carta` (preferência ampla). `Lista de desejos → variante` (intenção específica de aquisição).

## 2. Matriz de decisões D1–D9

| # | Decisão do proprietário | Registro canônico | Relação com o já aprovado |
|---|---|---|---|
| D1 | Binária, sem quantidade | C-210 / LDM-86 | Reafirma C-98 |
| D2 | Sem prioridade, ranking ou ordenação manual | C-210 | Reafirma C-98 (ranking) |
| D3 | Sem vínculo estrutural com Collection; inclusão contextual de faltantes | C-211, C-212 / LDM-204 | Aplica C-95 como comportamento de produto; ajusta o texto do V1-11 no ROADMAP |
| D4 | Indicador de posse e sugestão de remoção explícita | C-213 | Comportamento assistido previsto em C-93 |
| D5 | Variante desativada permanece registrada, sinalizada | C-214 / LDM-205 | Lacuna nova (não havia equivalente à C-90) |
| D6 | Interface "Lista de desejos"; termo técnico Wishlist | North Star N27 | Nomenclatura nova |
| D7 | Ícone bookmark, distinto do coração de Favoritos | Este documento §8 | Reforça C-97 na interface |
| D8 | Entradas obrigatórias: Pesquisa, Acervo, Set, Master Set, Pokédex e Fichário | C-215 | Novo, dentro de C-91/C-95 |
| D9 | Preço NM por variante, com cobertura e estados de indisponibilidade | C-216 / LDM-206 | Aplica NS-20 e `05f` V1-09 sem alterar Pricing |
| — | Privacidade e consentimento próprio da Conexão Inteligente | C-217 / LDM-207 | Reafirma C-158, C-174 |
| — | Fronteira CI-N1/CI-N2 | C-218 | Aplica C-53, C-101 e ROADMAP Etapa 4 |
| — | Inclusão a partir de conteúdo compartilhado (L6) | C-219 / LDM-208 | Compatível com C-157–C-163 e V1-12 (§5-A) |

## 3. Contrato conceitual do item

| Elemento | Regra |
|---|---|
| Identidade | Identificador estável por desejo (o CI-N2 poderá referenciar a intenção). |
| Dono | Sempre o usuário autenticado; nunca informado pelo cliente (C-102, C-217). |
| Variante | Obrigatória (C-91). Inclusão só em variante **ativa** no momento da inclusão (C-214). |
| Idioma | Opcional; vazio = **qualquer idioma** (C-92). Nunca "nenhum". |
| Data de inclusão | Registrada; base da ordenação "recentes" e da idade da intenção. |
| Unicidade | Usuário + variante + condição de idioma, com "qualquer" tratado como valor próprio (C-99). Repetir a inclusão não cria segunda entrada. |
| Múltiplos idiomas | "Aceito PT ou EN" = duas entradas legítimas (C-99); nenhum campo de lista de idiomas. |

**Derivados na leitura, nunca gravados:** carta, Set, número, imagem, nome legível da variante, estado de posse (C-213), preço NM da variante (C-216), favorito sim/não, variante ativa/desativada (C-214).

**Nunca existem no item:** quantidade, prioridade, ranking, ordem manual, preço-alvo, alerta, condição, graduação, vínculo com coleção/fichário/posição, visibilidade ou consentimento (C-210, C-211, C-217).

## 4. Regras de inclusão

### 4.1 Identificação inequívoca (C-212)

A inclusão direta só acontece quando a **variante** está inequivocamente identificada pelo contexto. Posição só com espécie, referência incompleta ou carta com mais de uma variante ativa possível **não autoriza inclusão automática**: havendo contexto suficiente, a interface oferece seleção explícita de carta e variante; sem contexto suficiente, a ação não é oferecida. Nunca se infere acabamento, variante ou idioma, e **nenhuma posição faltante vira desejo automaticamente** — todo desejo nasce de uma ação explícita do usuário, inclusive no lote. Idioma: o padrão é "qualquer idioma" (ausência, C-92), não uma inferência; o idioma específico só entra por escolha do usuário.

| Contexto conhecido | Variante identificada? | Comportamento |
|---|---|---|
| Variante exata (exemplar do acervo, reserva com variante, posição com exemplar) | Sim | Inclusão direta |
| Carta + acabamento (Master Set, reserva por acabamento) | Só se houver **uma** variante ativa daquele acabamento — a unicidade carta + acabamento não é garantida quando há perfis de impressão (`2171`) | Direta se única; senão escolha |
| Só a carta (Set, Pesquisa, reserva só por carta) | Só se a carta tiver **uma** variante ativa | Direta se única; senão escolha |
| Só a espécie (Pokédex sem carta) | Não | Escolha de carta e variante (ver lacuna L3, §10) |
| Nada (bolso vazio sem reserva) | Não | Ação não oferecida no bolso (lacuna L4, §10) |

### 4.2 Pontos de entrada obrigatórios (C-215)

| Entrada | Contexto disponível | Comportamento |
|---|---|---|
| **Pesquisa** | carta | §4.1; escolha via leitura de variantes da carta (`get_catalog_card_variants_for_picker`, `5163`) |
| **Acervo** | variante + idioma do grupo/exemplar | Direta ("Quero outra"), idioma padrão "qualquer", refinamento opcional |
| **Set** (Set padrão) | carta da posição | §4.1; posição possuída: desejar outra cópia da variante possuída |
| **Master Set** | carta + acabamento da posição | §4.1 |
| **Pokédex** | espécie (posição faltante) ou exemplar representante (posição ocupada) | Ocupada: variante do exemplar, direta. Faltante: escolha (L3) |
| **Fichário** | estado do bolso (`5223`) | Quatro cenários, §5 |
| **Conteúdo compartilhado** (coleção ou fichário de terceiro com acesso legítimo) | o que a leitura compartilhada já entrega | §5-A |

Granularidades respeitadas: Set padrão → carta (uma por posição); Master Set → carta + acabamento; Pokédex → espécie (posição faltante) ou exemplar representante (posição ocupada). A granularidade da posição nunca é "promovida" a variante sem identificação inequívoca.

Inclusão de **faltantes em lote** (Set, Master Set): apresenta prévia separando *inclusões diretas*, *já na lista* e *exigem escolha*; só as diretas são gravadas sem nova interação; as ambíguas nunca recebem variante presumida. Lote idempotente: repetir não duplica.

### 4.3 Contexto Collection (C-211)

Incluir a partir de uma coleção, de um fichário ou de uma posição **não cria vínculo** entre o desejo e essa estrutura. O desejo pertence só ao usuário; excluir, arquivar ou desmontar a coleção/fichário não altera a lista. Indicadores como "falta em alguma coleção" são **calculados** na leitura, nunca gravados.

## 5. Fichário — os quatro cenários (C-215)

Compatibilidade verificada contra a leitura canônica `get_my_collection_binder_pages` (`5223`/`5230`), que devolve por bolso `slot_state` (`EMPTY` / `RESERVED_EMPTY` / `OCCUPIED_UNPLANNED` / `OCCUPIED_MATCH` / `OCCUPIED_MISMATCH`), o conteúdo planejado (`expected_card_id`, `expected_card_variant_id`, `expected_variant_type_id`, exclusivos entre variante e acabamento pela `5225`) e o exemplar presente (`present_card_variant_id`, `present_language_code`).

| # | Cenário | Contrato vigente | Comportamento |
|---|---|---|---|
| 1 | Bolso vazio com variante conhecida (`RESERVED_EMPTY` com `expected_card_variant_id`, ou carta + acabamento com variante ativa única) | Compatível | Inclusão direta |
| 2 | Bolso vazio sem variante conhecida (`RESERVED_EMPTY` só com carta, ou carta + acabamento com mais de uma variante ativa) | Compatível | Escolha explícita da variante (§4.1) |
| 3 | Bolso ocupado (`OCCUPIED_*`) | Compatível (`present_card_variant_id`) | "Desejar outra cópia" da variante presente; idioma padrão "qualquer", refinamento opcional |
| 4 | Nenhum desejo pertence ao fichário ou ao bolso | Compatível por construção (C-211) | O fichário só oferece o atalho |

Restrições preservadas: o bolso planejado é apresentado como "Planejado para este bolso" e **nunca** como faltante (N22, C-42); bolso com imagem personalizada, região mesclada ou referência de espécie (C-198, C-199) não identifica variante — ver L4/L5. A ação é do titular no próprio fichário; a visão de membro/visitante não oferece a ação (L6).

## 5-A. Conteúdo compartilhado (C-219)

Um usuário **autenticado** pode adicionar um desejo à **própria** lista a partir de coleção ou fichário compartilhado ao qual tenha acesso legítimo (participante da coleção, V1-12; ou fichário público visto por usuário autenticado). Regras:

- a inclusão não altera a coleção, o fichário, a alocação nem o exemplar compartilhado, e não cria participação (C-163);
- o desejo é exclusivamente pessoal e privado; o titular e os demais participantes não o veem em razão do compartilhamento (C-158, C-217);
- a ação usa **somente** o que a leitura compartilhada já entrega ao usuário e nunca amplia permissões; sem a variante identificada por essa leitura, aplica-se a seleção explícita (§4.1);
- visitante anônimo não tem lista de desejos.

Compatibilidade verificada com os contratos de compartilhamento canônicos:

| Leitura compartilhada | O que entrega | Comportamento |
|---|---|---|
| Galeria da coleção (`get_shared_collection_cards`, `5313`) | `card_variant_id` + idioma (face pública já exposta ao participante) | Inclusão direta da variante |
| Posições da coleção (`get_shared_collection_positions`, `5320`) | `card_id` (carta da posição) | §4.1 por carta: direta só com variante ativa única; senão seleção explícita |
| Fichário do participante e vitrine pública (`5316`/`5318` → `collection_binder_masked_pages`, `5315`) | rótulos públicos (nome, número, Set, variante, idioma); **nunca** ids de carta ou variante, por desenho do mascaramento | Nenhuma inclusão direta; no máximo seleção explícita a partir dos rótulos visíveis, sem alterar o mascaramento (lacuna L6 para a W1) |

## 6. Posse (C-213)

Estado derivado, nunca gravado, em quatro níveis: tem esta variante neste idioma · tem a variante em outro idioma · tem outra variante da carta · não tem. "Qualquer idioma" conta qualquer exemplar da variante. Após registrar no acervo um exemplar que satisfaz um desejo, a interface pode **sugerir** "Remover da lista de desejos?"; a remoção só ocorre por ação explícita (C-93). Nunca há remoção automática.

## 7. Preço e indicadores (C-216)

- Preço por desejo: referência **NM por variante** (`get_card_variants_pricing_summary`, `3983`; regras do V1-09 em `05f`), com os estados já vigentes (atualizado, desatualizado, data desconhecida no `CARD_FALLBACK`, câmbio indisponível, sem preço). Preço ausente nunca vale zero. Outros idiomas usam a referência internacional (D4 do V1-09).
- **Contagem de desejos:** por combinação variante + condição de idioma (cada desejo conta uma vez).
- **Valor agregado de referência:** cada **variante distinta** contribui **uma única vez**; preferências de idioma sobrepostas da mesma variante ("qualquer" e "JP", por exemplo) **não duplicam** a soma; nunca multiplica por exemplares possuídos.
- **Cobertura financeira:** número de **variantes distintas com cotação válida** sobre o número de **variantes distintas** da lista — não sobre o total de desejos. Sem cobertura → "—", nunca "R$ 0"; preço ausente nunca equivale a zero.
- **Natureza da referência:** a referência NM é indicação de mercado; **não** representa compromisso de compra, preço-alvo nem valor patrimonial (o desejo não é posse).
- Nenhuma regra canônica de Pricing é alterada; nenhuma exibição pública de preço (D3 do V1-09).

## 8. Experiência (D6, D7)

- Nome na interface: **Lista de desejos** (N27). Termo técnico, código e documentação: Wishlist.
- Ícone **bookmark**, distinto do coração de Favoritos; dourado reservado ao estado ativo. Os dois controles podem coexistir no mesmo card sem se confundir (C-97).
- Página dedicada no padrão premium aprovado (hero, painel de indicadores do V1-10 com o valor em linha inteira no mobile, grade com a carta como protagonista, selos discretos de variante, idioma e posse, preço na etiqueta inferior esquerda do V1-09).
- Filtros e ordenações sem ranking: recentes, Set/número, preço; filtros por Set, posse, idioma e "falta em alguma coleção". Seleção múltipla para remover.
- Feedback imediato (otimista, com desfazer), estados vazio/erro/sem preço/variante desativada, mobile e desktop, teclado, `aria-pressed` com nome da carta e variante, `prefers-reduced-motion` (NS-12).

## 9. Privacidade e Conexão Inteligente (C-217, C-218)

- Privada por padrão: nunca exibida a visitantes, membros de coleção, outros usuários, histórico de atividades ou leituras públicas (C-158, C-174, regras de compartilhamento V1.0).
- A futura Conexão Inteligente exige **consentimento próprio**, em domínio separado; nada no item da Wishlist representa consentimento.
- **CI-N1** (Nível 1 da Etapa 4, "usa a Wishlist pessoal"): funcionamento **não definido**. **CI-N2** (Nível 2): cruzamento futuro de intenções com exemplares **voluntariamente disponibilizados**. Os rótulos CI-N1/CI-N2 evitam conflito com as entradas N1/N2 da nomenclatura da North Star.
- Disponibilidade para negociação (C-53) ≠ posse: nenhum exemplar do acervo é presumido disponível. Consentimento, localização e disponibilidade são domínios separados, nenhum modelado. Marketplace e pagamentos fora (C-101, ROADMAP).
- O que a Wishlist já entrega ao futuro CI: variante + idioma explícitos, identificador estável, data da intenção, unicidade e isolamento — sem precisar ser reconstruída.

## 10. Lacunas registradas (não inventadas)

| # | Lacuna | Efeito | Encaminhamento |
|---|---|---|---|
| L1 | Não existe leitura de "estado de desejo" por lote de cartas/variantes para pintar ícones | Necessária às seis entradas | W1 |
| L2 | Leituras de posição de Set/Master Set/Pokédex (`5169`, `5189`/`5198`, `5204`) e a compartilhada `5320` não devolvem variantes ativas candidatas da posição | Prévia de faltantes em lote e seleção explícita | W1 investiga: composição com `5163` ou leitura nova |
| L3 | Não há leitura para usuário que liste cartas de uma **espécie** para escolha em posição Pokédex faltante | Pokédex faltante não tem inclusão direta | W1 deve propor; até lá, a entrada da Pokédex cobre posições ocupadas e encaminha a faltante à escolha por carta |
| L4 | Bolso `EMPTY` sem reserva não identifica carta | Cenário fora dos quatro aprovados | Ação não oferecida; nenhum comportamento inventado |
| L5 | Bolso com referência de espécie (C-199) sem exemplar só identifica a espécie | Igual a L3 | Igual a L3 |
| L6 | **Regra decidida (C-219, §5-A).** Lacuna técnica remanescente: o fichário compartilhado e a vitrine pública (`5315`) não expõem ids de carta/variante, por desenho | Inclusão a partir do fichário compartilhado só por seleção explícita | W1 investiga uma seleção explícita a partir dos rótulos já visíveis, **sem** alterar o mascaramento nem ampliar permissões |
| L7 | CI-N1 sem definição funcional; disponibilidade (C-53), consentimento e localização sem modelo nem versão | Etapa 4 | Fora do V1-11 |

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-10-31, `V1-11 W0 — PRODUCT CONTRACT CONSOLIDATION-02`).** Consolida D1–D9 do proprietário e o ajuste do Fichário como entrada obrigatória; registra C-210–C-218, LDM-204–LDM-207 e N27; quatro cenários do Fichário verificados contra `5223`/`5225`; lacunas L1–L7. C-91–C-102 e LDM-79–LDM-90 inalteradas. Sem SQL, código ou alteração visual. |
| 1.1 | **Ajustes da auditoria (2026-10-31, `V1-11 W0 DOCUMENTATION AUDIT CLOSEOUT-03`).** L6 decidida (C-219, LDM-208; §5-A com a compatibilidade conferida contra `5313`, `5320`, `5315`/`5316`/`5318`); §4.1/§4.2 explicitam que posição só com espécie, referência incompleta ou carta ambígua não autoriza inclusão automática e que nenhuma posição faltante vira desejo automaticamente; §7 explicita contagem por variante + idioma, cobertura sobre variantes distintas com cotação válida e natureza da referência NM; L2/L6 reescritas. Pricing inalterado. |
