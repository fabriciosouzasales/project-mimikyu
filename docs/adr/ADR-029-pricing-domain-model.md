# ADR-029 — Pricing Domain Model

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-029 |
| **Título** | Pricing Domain Model |
| **Status** | Aprovado |
| **Data** | 2026-08-16 |
| **Decisores** | Project Mimikyu |
| **Decisão** | Pricing é um quarto domínio conceitual, independente de Catálogo Editorial, Patrimônio do Usuário (Ownership) e Analytics — nunca um apêndice de nenhum dos três. Modelado como dez entidades próprias (`pricing_source` até `pricing_sync_run_call`, ver `05f-pricing.md`), sem reaproveitar `asset_source`/`card_external_reference`/`card_set_external_reference`/`catalog_admin_action_log` do Catálogo Editorial. Nenhuma tabela foi criada — esta é uma decisão de modelagem, não de implementação. |
| **Documentos Relacionados** | `ADR-006-separation-of-catalog-ownership-and-analytics.md`, `ADR-008-external-catalog-data-sources.md`, `ADR-013-collection-item-identity-model.md`, `ADR-028-card-variant-governance.md`, `../04-domain-model.md`, `../05f-pricing.md`, `../standards/STD-001-database-standards.md`, `../standards/STD-002-domain-modeling.md` |

---

# Context

Em 2026-08-16, Fabrício aprovou a sequência estratégica **Card Variant (fundação encerrada) → Pricing/Market Data → Collection → Analytics/Valuation** (`ROADMAP.md`), tornando Pricing a próxima frente comprometida do projeto. Um discovery anterior, na mesma data, já havia pesquisado fontes de mercado candidatas (JustTCG, TCGdex embutindo Cardmarket/TCGplayer), estratégia de conversão para BRL (PTAX do Banco Central) e estratégia de histórico (snapshots próprios) — mas era material de apoio à decisão, não uma modelagem aprovada, e permanece assim: a homologação técnica de qualquer fonte (JustTCG, especificamente) segue em paralelo, **sem concluir** no momento desta decisão — a prova técnica (`PROVA-TECNICA-JUSTTCG-PRICING-2026-08-16.md`, fora de `docs/`) foi interrompida por limitação operacional de cota, não por aprovação nem reprovação da fonte.

Esta ADR resolve uma pergunta diferente e anterior à homologação de qualquer fonte específica: **onde e como Pricing se encaixa na arquitetura já estabelecida do projeto**, de forma que a modelagem permaneça válida independentemente do resultado da homologação da JustTCG ou de qualquer outra fonte.

Havia uma hipótese inicial de nomes de tabela (`pricing_sources`, `pricing_set_mappings`, `pricing_card_mappings`, `pricing_products`, `pricing_condition_mappings`, `pricing_observations`, `pricing_sync_runs`, `item_valuation_snapshots`) fornecida como ponto de partida para confronto contra os padrões reais do repositório — não como modelo já aprovado.

---

# Decision

## Pricing é um quarto domínio, não um apêndice

`ADR-006` já separa o domínio em três responsabilidades — Catálogo Editorial, Patrimônio do Usuário (Ownership), Analytics. Pricing não pertence a nenhuma das três sem distorção (ver `05f-pricing.md`, seção "Por que Pricing é um Domínio Independente", para o racional completo): não é dado editorial oficial (Catálogo), não pertence a nenhum usuário especificamente (Ownership), e não é puramente derivado de Catálogo+Ownership (Analytics) — é, ele mesmo, um dado primário importado de terceiros, com seu próprio ciclo de staging/confirmação/auditoria, que Analytics consumirá depois.

`ADR-008` (fontes externas nunca são dependência estrutural em tempo real — sempre um pipeline `fonte → importação → catálogo interno soberano`) é estendida, pela primeira vez, para além do Catálogo Editorial: o mesmo princípio rege como Pricing consome fontes externas de preço.

## Dez entidades descritas, nove próprias de Pricing, modelo detalhado em `05f-pricing.md`

`pricing_source`, `card_condition` (referência compartilhada, não exclusiva de Pricing — corrigido em 2026-08-16, ver "Correção Arquitetural Pontual", abaixo), `pricing_condition_mapping`, `pricing_set_mapping`, `pricing_card_mapping`, `pricing_product`, `pricing_fx_rate`, `pricing_observation`, `pricing_sync_run`, `pricing_sync_run_call` — modelo lógico e físico completo (colunas, tipos, obrigatoriedade, PKs/FKs, uniques, checks, índices, cardinalidades, política de exclusão, RLS/grants, imutabilidade) em `05f-pricing.md`. Nenhuma tabela foi criada no Supabase.

## Nenhuma tabela do Catálogo Editorial é reaproveitada por Pricing

Apesar do padrão estrutural de `asset_source`/`card_external_reference`/`card_set_external_reference` (Catálogo Editorial, `05c-assets-e-importacao.md`) ser deliberadamente **repetido** por Pricing — mesma disciplina já validada em produção —, nenhuma dessas tabelas é referenciada fisicamente por uma tabela de Pricing. `pricing_source` é uma tabela própria, distinta de `asset_source`; `pricing_set_mapping`/`pricing_card_mapping` são tabelas próprias, distintas de `card_set_external_reference`/`card_external_reference`. Ver "Alternatives Considered" para o racional dessa escolha.

## Preço, condição, idioma e printing são dimensões independentes — nunca colapsadas

Herdado das correções conceituais já validadas durante a prova técnica da JustTCG (revisão 2 do documento de prova) e agora formalizado como decisão de modelagem permanente:

- **printing ≠ condição.** Só o acabamento/impressão (`printing`) tem relação com `Card Variant` (`ADR-028`) — condição de conservação nunca cria nem qualifica um `card_variant`; pertence à cotação (`pricing_observation.condition_id`, referenciando `card_condition` — ver nota de correção abaixo) e, futuramente, ao item físico do usuário (Ownership), nunca ao Catálogo. Reforça `ADR-006` diretamente.
- **moeda ≠ mercado.** `pricing_observation.currency_code` (a moeda em que o preço foi reportado) e `pricing_observation.market_label` (o mercado/mecanismo que originou o preço, ex.: TCGplayer vs. Cardmarket dentro de uma mesma fonte agregadora) são colunas independentes — uma fonte pode reportar mais de uma moeda para mercados diferentes que ela agrega (achado real do discovery: o campo `pricing` embutido da TCGdex combina Cardmarket em EUR e TCGplayer em USD).
- **cobertura de catálogo ≠ cobertura de idioma/impressão ≠ cobertura de mercado.** Modeladas como três perguntas distintas e independentes, nunca combinadas numa única resposta binária: `pricing_card_mapping.match_status` responde "esta é a mesma Card?" (`CONFIRMED`/`PENDING`/`NOT_FOUND`/`REJECTED` — ver correção de precisão abaixo); `pricing_product.language_status`/`language_id`/`card_variant_id` respondem "esta é a mesma impressão/idioma?"; `pricing_observation.market_scope`/`market_evidence` respondem "este preço específico vem de qual tipo de mercado, com que evidência?" (não mais `pricing_source.default_market_scope` isoladamente — ver correção abaixo). Uma Card pode estar `CONFIRMED` em `pricing_card_mapping` e ainda assim não ter nenhuma classificação de valuation por item, se a segunda ou a terceira pergunta não forem satisfeitas.

## Correção Arquitetural Pontual (2026-08-16, mesma data, ciclo seguinte)

Cinco pontos corrigidos a pedido explícito de Fabrício, sem reabrir a modelagem inteira nem as decisões já corretas acima. Detalhamento completo, por entidade, em `05f-pricing.md` revisão `1.1`. Resumo normativo:

1. **Idioma não pode ser modelado em função de PT-BR.** `pricing_product.language_status` generalizado de tri-estado binário (`CONFIRMED`=PT-BR / `NOT_CONFIRMED`=não-PT-BR / `UNDETERMINED`) para tri-estado neutro e multi-idioma: `CONFIRMED` (idioma explícito e confiável, qualquer idioma) / `INFERRED` (idioma inferido por heurística, sem declaração dedicada da fonte) / `UNDETERMINED`. `confirmed_language_id` renomeado para `language_id` (obrigatório em `CONFIRMED`/`INFERRED`, nulo em `UNDETERMINED`). Cobertura de um idioma específico (PT-BR ou qualquer outro) passa a ser sempre **derivada por comparação** — `pricing_product.language_id = collection_item.language_id` (futuro) —, nunca lida de um campo binário. Valuation direto exige `language_status = 'CONFIRMED'`; `INFERRED` não autoriza equivalência direta do item.
2. **"Valor Brasil" deve depender da evidência de mercado da observação, não só da fonte.** `pricing_source.market_scope` renomeado para `default_market_scope` — passa a ser classificação/capacidade declarada e default, nunca mais autoridade final. `pricing_observation` ganha `market_scope` (`INTERNATIONAL`/`BRAZIL`/`UNDETERMINED`), `market_label` (renomeado de `market`, mesmo propósito) e `market_evidence` (`JSONB`, evidência normalizada). Nova regra obrigatória: `BRAZIL_ITEM_VALUATION` só é autorizada quando a observação usada como base tiver `market_scope = 'BRAZIL'` **e** `market_evidence_confirmed = TRUE` — a classificação da fonte, isoladamente, nunca basta. Motivado por fontes agregadoras que reportam mais de um mercado ao mesmo tempo (ex.: JustTCG combina Cardmarket/TCGplayer, ambos internacionais); fixar a decisão só na fonte impediria representar corretamente uma futura fonte BR que também agregue um mercado internacional secundário, sem duplicar artificialmente o cadastro da fonte.
3. **Distinguir ausência confirmada de nunca testado.** `pricing_set_mapping`/`pricing_card_mapping` ganham um quarto estado, `NOT_FOUND` — consulta tecnicamente concluída sem correspondência localizada, distinta de (a) ausência de linha (nunca avaliado) e de (b) `REJECTED` (um candidato específico, encontrado e explicitamente rejeitado). A versão `1.0` continha exatamente essa contradição: tratava `REJECTED` como cobrindo simultaneamente "candidato rejeitado" e "busca concluída sem candidato algum" — corrigido. Falha técnica nunca gera `NOT_FOUND` (permanece só em `pricing_sync_run_call.outcome = 'TECHNICAL_FAILURE'`). `external_set_id`/`external_card_id` tornam-se opcionais, obrigatórios só em `CONFIRMED`; a `UNIQUE` simples de `(fonte, id externo)` foi substituída por um índice único parcial (`WHERE match_status = 'CONFIRMED'`), para não impedir que o mesmo candidato externo seja avaliado e descartado para mais de uma Card/Set ao longo do tempo. Novo campo `last_checked_at`, porque a cobertura de uma fonte externa pode mudar no futuro.
4. **Condição canônica deve ser referência compartilhada.** `pricing_condition` renomeada para `card_condition` e reclassificada como referência compartilhada e neutra — não pertence a Pricing nem ao Catálogo Editorial, para que `Collection Item` (Ownership, futuro) não precise depender de uma tabela nominalmente pertencente a Pricing só porque foi definida ali primeiro. `pricing_condition_mapping` permanece entidade própria de Pricing, agora referenciando `card_condition`. O total de entidades descritas em `05f-pricing.md` permanece 10, mas apenas 9 são exclusivas do domínio Pricing.
5. **Diagrama Mermaid corrigido.** Removidas as relações `CARD_VARIANT`↔`LANGUAGE` e `PRICING_FX_RATE`↔`PRICING_OBSERVATION` do ER — ambas já eram declaradas, no próprio texto da versão `1.0`, como não tendo FK física, o que as tornava contraditórias como relações desenhadas. Movidas para nota textual, fora do diagrama.

Nenhuma tabela criada, nenhuma migration, nenhuma chamada à API da JustTCG nesta correção. A condição da homologação da JustTCG permanece inalterada (pendente, não aprovada nem reprovada), assim como os critérios pré-registrados das Decisões A/B, intocados.

## "Valor Brasil" é uma propriedade da observação com evidência de mercado, nunca da fonte isolada nem da conversão de moeda

**Corrigido em 2026-08-16 (ver "Correção Arquitetural Pontual", acima)** — a versão original desta ADR atribuía essa autoridade exclusivamente a `pricing_source.market_scope`. `pricing_observation.market_scope` (`INTERNATIONAL`/`BRAZIL`/`UNDETERMINED`) combinado com `market_evidence_confirmed = TRUE` é o mecanismo que autoriza a classificação futura `BRAZIL_ITEM_VALUATION` (Analytics, ver `05f-pricing.md`, seção "Item Valuation") — `pricing_source.default_market_scope` é apenas a classificação/default declarado da fonte, nunca suficiente sozinha. Nenhuma conversão de `pricing_fx_rate` (USD→BRL) promove uma fonte ou uma observação internacional a "Valor Brasil" — a conversão é sempre informativa, nunca persistida sobre o preço original (`pricing_observation.price`/`currency_code` são imutáveis), e nunca muda `market_scope`/`market_evidence_confirmed` da observação que a originou.

## Preço é imutável — histórico nunca é sobrescrito

`pricing_observation` e `pricing_fx_rate` não têm coluna `updated_at` — divergência deliberada do "Padrão Mínimo" de auditoria do STD-001 (Seção 4: `id`/`created_at`/`updated_at`), justificada porque ambas são tabelas de fato de série temporal (log de eventos imutável), não entidades de negócio mutáveis. Nenhuma role de aplicação recebe `UPDATE`/`DELETE` nelas. Idempotência (nunca duplicar a mesma observação) é garantida por `UNIQUE` + `ON CONFLICT DO NOTHING`, mesmo padrão já exigido de Seeds pelo STD-001.

## Auditoria de sincronização em dois níveis, com precedente já validado em produção real

`pricing_sync_run` (execução, nível alto) e `pricing_sync_run_call` (cada chamada individual — endpoint, status HTTP, resultado lógico de três estados, cota restante, erro sempre sanitizado) não são uma invenção especulativa: espelham diretamente o mecanismo já **implementado e exercitado contra a API real da JustTCG** no script local da prova técnica (`Executar-ProvaJustTCG-Fase-A-B.ps1`) — contrato de três estados (`Sucesso`/`FalhaTecnica`/`OrcamentoInterrompido`), log duplo de retry após `429`, teto de segurança de cota, e redação defensiva de qualquer padrão de chave de API antes de persistir qualquer texto de erro. A modelagem eleva um mecanismo já comprovado a schema permanente, em vez de desenhá-lo do zero.

---

# Consequences

## Benefícios

- Pricing pode ganhar, perder ou substituir fontes (JustTCG, TCGplayer, uma futura fonte brasileira) sem reconstrução funcional — toda tabela referencia `pricing_source.id`, nunca o nome de uma fonte específica;
- a rejeição ou aprovação da JustTCG (ainda pendente) não bloqueia nem invalida nenhuma linha desta modelagem — o modelo é genérico por fonte desde a primeira entidade;
- a separação entre correspondência de Card (`pricing_card_mapping`), correspondência de impressão/idioma (`pricing_product`) e evidência de mercado por observação (`pricing_observation.market_scope`/`market_evidence_confirmed`, corrigido em 2026-08-16 — antes só `pricing_source.market_scope`) torna impossível, por construção, que uma impressão internacional receba automaticamente o rótulo "Valor Brasil" ou o valor de uma cópia de qualquer idioma específico do usuário;
- o histórico de preço nunca é perdido por sobrescrita, e toda conversão de moeda é rastreável até a taxa e a data exatas usadas;
- a auditoria de sincronização (execução + chamada individual) já nasce no mesmo padrão de rigor comprovado pela prova técnica real, incluindo a disciplina de nunca persistir segredo.

## Restrições / Pendências

- nenhuma tabela foi criada — a implementação física é um ciclo futuro próprio, condicionado à conclusão (aprovação, reprovação, ou aprovação parcial só para a Decisão A) da homologação de pelo menos uma fonte, para que a primeira seed real (`pricing_source`, `pricing_condition_mapping`) tenha dado real para se apoiar;
- a policy de leitura de Pricing para usuário final (não-admin) permanece em aberto — só será desenhada quando Collection existir e precisar exibir preço estimado ao colecionador, mesmo padrão de pendência já registrado em `ADR-028` para o seletor de Card Variant;
- `item_valuation_snapshot` (Analytics) é apenas esboçada conceitualmente em `05f-pricing.md` — sua modelagem física fica para quando Collection existir, por depender de `collection_item_id`, que ainda não tem tabela;
- o risco legal de redistribuição comercial de dado de preço (Cardmarket/TCGplayer, identificado no discovery) não é resolvido por esta ADR — `pricing_source.requires_commercial_agreement`/`terms_url`/`attribution_text` dão à modelagem um lugar para essa informação viver, sem decidir a questão jurídica.

---

# Alternatives Considered

## Reaproveitar `asset_source`/`card_external_reference`/`card_set_external_reference` do Catálogo Editorial

Rejeitada. Embora estruturalmente quase idênticas, essas tabelas representam fontes de **sincronização de catálogo/imagem** (TCGdex, importação manual), um domínio já com seu próprio ciclo de vida, RLS e função administrativa. Pricing precisa, além disso, de campos que o Catálogo nunca precisou (`match_status`/`match_method`/`match_evidence`/`confirmed_at`/`confirmed_by` em nível de correspondência; `market_scope`/`base_currency`/`requires_commercial_agreement` em nível de fonte) — forçar esses campos dentro das tabelas do Catálogo Editorial misturaria dois domínios que `ADR-006` já mandou manter separados, e tornaria impossível evoluir Pricing (ex.: adicionar um novo `market_scope`) sem tocar em uma tabela que o Catálogo Editorial também depende. Mesmo raciocínio já usado para não reaproveitar `admin_action_log` em `catalog_admin_action_log` (`ADR-021`) e para não emendar `ADR-006` na criação de `ADR-027`.

## Tratar Pricing como uma extensão de `Card Variant`

Rejeitada. `Card Variant` (`ADR-028`) é dado editorial permanente (existe independentemente de qualquer fonte de preço observar ou não aquela impressão); Pricing é dado de mercado, volátil, de terceiros. Colapsar os dois violaria diretamente `ADR-006` e a correção conceitual já registrada na revisão 2 da prova técnica da JustTCG (printing ≠ condição, Pricing é domínio próprio, não sub-tabela de Catálogo).

## Persistir a classificação de valuation (`INTERNATIONAL_ITEM_VALUATION` etc.) como coluna de Pricing

Rejeitada nesta rodada. A classificação depende de um Collection Item concreto (Ownership), que ainda não existe — persistir a classificação em Pricing hoje seria antecipar uma junção que só faz sentido quando Ownership existir, além de violar o princípio de não persistir dado derivado sem justificativa concreta (`ADR-006`). Tratada como Analytics futura (`item_valuation_snapshot`, esboçado, não implementado) — ver `05f-pricing.md`.

## Não separar chamada individual (`pricing_sync_run_call`) de execução (`pricing_sync_run`)

Rejeitada. A prova técnica da JustTCG já demonstrou, em ambiente real, o valor concreto dessa granularidade (diagnosticar exatamente qual chamada recebeu `429`, confirmar a cota restante a cada instante, isolar uma falha técnica específica dentro de uma execução maior) — resumir tudo a um único registro por execução perderia informação já comprovadamente útil.

---

# Related Documents

- `ADR-006-separation-of-catalog-ownership-and-analytics.md`
- `ADR-008-external-catalog-data-sources.md`
- `ADR-013-collection-item-identity-model.md`
- `ADR-028-card-variant-governance.md`
- `../04-domain-model.md`
- `../05f-pricing.md`
- `../standards/STD-001-database-standards.md`
- `../standards/STD-002-domain-modeling.md`
- `../ROADMAP.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza Pricing como quarto domínio conceitual independente (Catálogo/Ownership/Analytics/Pricing), a separação definitiva entre printing/condição/idioma/mercado/moeda, a regra de que "Valor Brasil" é propriedade exclusiva da fonte (`market_scope`) e nunca de conversão cambial, a imutabilidade de `pricing_observation`/`pricing_fx_rate`, e a auditoria de sincronização em dois níveis já validada pela prova técnica real da JustTCG. Modelo físico completo em `05f-pricing.md`. Nenhuma tabela criada; homologação de fonte (JustTCG) segue pendente, em paralelo, sem bloquear esta decisão. |
| 1.1 | **Correção arquitetural pontual (2026-08-16, mesmo dia, ciclo seguinte)**, a pedido explícito de Fabrício — cinco pontos, sem reabrir a modelagem: (1) idioma de `pricing_product` generalizado de tri-estado binário-PT-BR para tri-estado neutro multi-idioma (`CONFIRMED`/`INFERRED`/`UNDETERMINED` + `language_id`), cobertura derivada por comparação com o idioma do Collection Item, valuation direto exigindo `CONFIRMED`; (2) "Valor Brasil" deixa de depender exclusivamente de `pricing_source.market_scope` (renomeado `default_market_scope`, agora só default declarado) e passa a exigir evidência na própria `pricing_observation` (`market_scope`/`market_label`/`market_evidence`/`market_evidence_confirmed`); (3) `pricing_set_mapping`/`pricing_card_mapping` ganham estado `NOT_FOUND` (busca concluída sem correspondência), corrigindo a contradição da v1.0 que colapsava isso sob `REJECTED`; identificadores externos tornam-se opcionais (obrigatórios só em `CONFIRMED`), `UNIQUE` simples substituída por índice único parcial, novo `last_checked_at`; (4) `pricing_condition` renomeada para `card_condition`, reclassificada como referência compartilhada e neutra, não exclusiva de Pricing; (5) diagrama Mermaid corrigido — removidas as relações `CARD_VARIANT`↔`LANGUAGE` e `PRICING_FX_RATE`↔`PRICING_OBSERVATION`, sem FK física, movidas para nota textual. Nenhuma tabela criada, nenhuma migration, nenhuma chamada à API da JustTCG; condição da homologação da JustTCG inalterada (pendente, não aprovada nem reprovada); critérios pré-registrados das Decisões A/B intocados. Decisões corretas da versão `1.0` preservadas integralmente. Detalhamento completo em `05f-pricing.md` revisão `1.1`. |
