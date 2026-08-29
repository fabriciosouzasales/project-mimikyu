# Collection — Benchmark de Produto e UX (PkmnBindr)

| Campo | Valor |
|--------|-------|
| **Documento** | Benchmark de Produto/UX — Referência PkmnBindr |
| **Arquivo** | `docs/domain-modeling/collections/pkmnbindr-benchmark.md` |
| **Origem** | Produzido em repositório de modelagem paralelo (`mimikyu-modelagem-de-dados`), incorporado a `project-mimikyu` em 2026-08-28 (pedido explícito de Fabrício). |
| **Natureza** | Produto / UX / Estratégia / Requisitos candidatos — **não normativo**. Não altera automaticamente `concept-decisions.md` nem `logical-model.md`. |
| **Status** | Benchmark inicial consolidado (15/08/2026) |
| **Documentos Relacionados** | `concept-decisions.md`, `logical-model.md`, `checkpoint-2026-08-28.md` (registra a decisão de produto de Collections como primeira superfície client-facing, motivada em parte por este benchmark). |

---

> **Nota de incorporação (2026-08-28).** Este documento é referência de produto/UX, não um decision register vinculante — nenhum item aqui vira decisão de modelagem só por constar deste arquivo (ver Seção 34 do próprio documento, "Impacto no checkpoint atual de modelagem": "não invalida as decisões já aprovadas"). Os requisitos candidatos `PX-01` a `PX-08` (Seção 28) e as prioridades `P0`/`P1`/`P2` (Seção 33) permanecem candidatos até validação formal em roadmap de produto.

---

# MMKYU Collector — Benchmark de Produto e UX
## Referência: PkmnBindr

**Status:** Benchmark inicial consolidado
**Data:** 15/08/2026
**Natureza:** Produto / UX / Estratégia / Requisitos candidatos
**Referência analisada:** PkmnBindr
**Escopo:** experiência de gerenciamento visual de binders, onboarding, operações em massa, busca, compartilhamento, portabilidade e integração digital–físico.

> Este documento registra aprendizados e hipóteses para o MMKYU Collector. Ele **não altera automaticamente decisões conceituais ou lógicas já aprovadas**. Qualquer impacto no modelo deverá ser formalmente decidido no fluxo de modelagem correspondente.

---

# 1. Objetivo do benchmark

O PkmnBindr foi identificado como uma referência relevante principalmente pela:

- velocidade de uso;
- baixa fricção;
- manipulação visual;
- importação de sets em poucos cliques;
- organização de grandes quantidades de cartas;
- representação de binder/páginas/slots;
- tratamento de variantes;
- compartilhamento;
- experiência mobile;
- portabilidade de dados.

O objetivo não é copiar o produto.

O objetivo é identificar padrões de interação, decisões de UX e capacidades que possam elevar:

- experiência do usuário;
- velocidade de onboarding;
- ativação;
- retenção;
- diferenciação;
- escalabilidade operacional;
- percepção de valor do MMKYU Collector.

---

# 2. Posicionamento observado

O PkmnBindr se apresenta essencialmente como uma ferramenta especializada em **organizar e desenhar binders digitais**, combinada com funcionalidades de acompanhamento de coleção.

Entre as capacidades publicamente apresentadas estão:

- adicionar sets inteiros;
- acompanhar variantes/printings;
- acompanhar preços;
- marcar cartas faltantes;
- ordenar e reorganizar centenas de cartas;
- criar layouts customizados;
- mesclar slots;
- compartilhar binders;
- importar e exportar dados;
- pesquisar cartas;
- usar o produto em dispositivos móveis.

## Insight para o MMKYU

O MMKYU não deve tentar ser apenas um binder designer melhor.

A experiência visual de binder deve ser uma das interfaces de um sistema mais profundo:

```text
MMKYU Collector
├── Canonical Catalog
├── Inventory
├── Collections
├── Completion
├── Card Variants
├── Ownership
├── Storage
├── Physical Organization
├── Digital Layout
├── Wishlist
├── Sharing
└── Intelligence
```

**Diretriz estratégica:** usar o PkmnBindr como referência de interação, velocidade e manipulação visual, sem reduzir o MMKYU à mesma categoria de produto.

---

# 3. Descoberta estrutural — Collection não é Binder

As telas analisadas reforçam uma separação que deve permanecer explícita no MMKYU:

```text
Collection
    │
    ├── Collecting Goal
    ├── Inventory Items
    └── Presentation / Layout
            │
            ├── Pages
            └── Slots
```

Uma Collection representa o objetivo colecionável.

O Layout representa como esse objetivo e/ou os Inventory Items são apresentados visualmente.

O Storage representa onde o exemplar físico realmente se encontra.

Portanto:

```text
Collection ≠ Layout ≠ Storage
```

Exemplo válido:

```text
Collection:
ME2.5 — Heróis Excelsos

Layout:
Carta exibida na página 18, slot 7

Storage:
Binder físico ME2.5
```

ou mesmo:

```text
Layout:
Carta exibida na página 18

Storage:
ETB Heróis Excelsos
```

A representação digital não deve obrigatoriamente espelhar a localização física.

---

# 4. Descoberta estrutural — Slot pode existir sem Inventory Item

Uma posição visual pode existir antes da posse física da carta.

Exemplo:

```text
Binder Slot
├── expected_card / expected_variant
└── inventory_item = NULL
```

Posteriormente:

```text
Binder Slot
├── expected_card / expected_variant
└── inventory_item = ITEM_004592
```

A identidade do Slot não deve ser recriada quando a carta for adquirida.

## Distinções essenciais

```text
Wishlist
"Quero adquirir esta carta."

Binder Slot
"Esta posição foi destinada a esta carta."

Inventory Item
"Possuo este exemplar físico."

Completion Requirement
"Esta carta/variante/posição é necessária para completar meu objetivo."
```

Consequentemente:

```text
Completion Requirement
        ≠
Binder Slot
        ≠
Inventory Item
        ≠
Wishlist Item
```

Essa separação deverá orientar o futuro modelo de Layout.

---

# 5. Bulk Collection Onboarding

Este foi o principal aprendizado do benchmark.

O PkmnBindr permite selecionar um Card Set e adicionar centenas de cartas através de um wizard curto.

O fluxo observado segue aproximadamente:

```text
1. Select Set
      ↓
2. Configure
   - placement
   - variants
   - capacity
      ↓
3. Review & Confirm
      ↓
4. Bulk operation
```

Em uma das capturas analisadas:

- 122 cartas do set;
- 76 Reverse Holo;
- 198 posições adicionadas;
- expansão automática de capacidade proposta;
- posicionamento das paralelas configurável.

## Insight MMKYU

O catálogo deve trabalhar para o usuário.

Se o MMKYU já conhece:

```text
Card Set
└── Cards
    └── Card Variants
```

não há razão para obrigar o colecionador a recadastrar manualmente informação canônica.

O usuário deve informar principalmente o que é pessoal:

- o que possui;
- quais variantes possui;
- Owner;
- Collection;
- Storage;
- exceções;
- preferências de completude.

---

# 6. Princípio de UX — esforço proporcional às exceções

Para Collections completas ou quase completas, o esforço não deve ser proporcional ao número total de cartas.

Deve ser proporcional às exceções.

Exemplo:

```text
Card Set: 295 requisitos

Tenho:
● Todas, exceto...
○ Somente as selecionadas

Faltam:
☐ 125
☐ 226
☐ 249
...
```

Em vez de selecionar 270 cartas possuídas, o usuário informa apenas as 25 faltantes.

## Diretriz

> O esforço de cadastro deve ser proporcional ao número de exceções, e não ao tamanho da Collection.

Esse princípio é particularmente importante para usuários avançados que chegam ao MMKYU com milhares de cartas e múltiplas Collections completas.

---

# 7. PX-01 — Bulk Collection Onboarding

**Requisito candidato de Produto/UX**

Collections baseadas em referências canônicas deverão permitir inicialização e declaração de posse em massa utilizando o conhecimento já existente no catálogo.

O fluxo deverá suportar, conforme aplicável:

- Card Set inteiro;
- Set Base;
- subconjuntos;
- variantes;
- seleção massiva;
- desmarcação por exceção;
- Collection completa;
- Collection quase completa;
- Standard Set;
- Master Set;
- Storage padrão;
- Owner;
- preview da operação.

A confirmação poderá resultar na criação de centenas ou milhares de Inventory Items sem exigir cadastro individual.

A operação deverá respeitar:

- `completion_policy`;
- Adopted Scope;
- Card Variant;
- Inventory Item Owner;
- Storage;
- regras de elegibilidade da Collection.

**Prioridade recomendada:** crítica para onboarding comercial.

---

# 8. Configuração de variantes em massa

O benchmark demonstra uma interação eficiente para variantes.

Exemplo observado:

```text
Card Variants

☑ Reverse Holo
   76 cards in this set
```

Também existem outras variantes disponíveis para seleção.

## Aplicação potencial no MMKYU

```text
VARIANTES

Base
✓ Normal                         122

Paralelas
✓ Reverse Holo                   76

Especiais
☐ Jumbo                           2
☐ League                          8
☐ Tournament                     4
```

O total da operação deve ser recalculado imediatamente.

Para `MASTER_SET`, essa interface poderá trabalhar diretamente com o Master Set Adopted Scope aprovado no modelo lógico.

## Princípio

Variant Type pode facilitar seleção em massa, mas a fonte de verdade do Master Set continua sendo a seleção explícita dos `card_variant_id` aplicáveis.

---

# 9. Placement das variantes

O benchmark apresenta alternativas como:

- Interleaved;
- All First;
- All Last.

Exemplo intercalado:

```text
001 Normal
001 Reverse
002 Normal
002 Reverse
003 Normal
003 Reverse
```

Exemplo agrupado:

```text
001 Normal
002 Normal
003 Normal
...
001 Reverse
002 Reverse
003 Reverse
```

## Insight

Essa preferência pertence ao Layout, não ao Card, Card Variant ou Inventory Item.

Ela deverá ser considerada quando o domínio de apresentação/layout for modelado.

---

# 10. PX-02 — Preview Before Bulk Mutation

**Requisito candidato de Produto/UX**

Toda operação em massa com impacto relevante deverá apresentar ao usuário, antes da confirmação, uma síntese clara das consequências.

Exemplo MMKYU:

```text
REVISAR IMPORTAÇÃO

ME2.5 — Heróis Excelsos

Serão criados:
295 Inventory Items

Owner:
Fabrício

Collection:
ME2.5 — Heróis Excelsos

Storage:
Binder ME2.5

Impacto:
295/295 requisitos satisfeitos
100% da Collection

[ Confirmar ]
```

O preview deverá informar, conforme a operação:

- registros criados;
- registros removidos;
- registros alterados;
- itens realocados;
- Storage afetado;
- Layout afetado;
- impacto na completude;
- conflitos;
- exceções;
- ações irreversíveis.

## Aplicações futuras

O princípio deve ser transversal:

- importação de Inventory Items;
- movimentação em massa;
- alteração de Master Set Scope;
- reorganização de Layout;
- alteração de Storage;
- transferências;
- arquivamentos;
- outras mutações de alto impacto.

---

# 11. Bulk Operations como capacidade transversal

O benchmark mostra que operações em massa não são apenas uma função de onboarding.

Elas aparecem em:

- inclusão de sets;
- aplicação de variantes;
- seleção múltipla;
- copy/paste;
- ordenação;
- reorganização;
- manipulação de páginas.

## Insight MMKYU

Bulk Operations deverá ser tratada como uma capacidade transversal de UX.

Potenciais domínios:

```text
Inventory
Collection
Storage
Layout
Wishlist
```

A experiência deverá privilegiar:

```text
Select
→ Configure
→ Preview
→ Confirm
```

---

# 12. PX-03 — Recoverability

O benchmark apresenta:

- Undo;
- Redo;
- histórico de alterações;
- Revert para último estado salvo.

## Insight

Quanto maior a capacidade de executar operações em massa, maior o custo percebido de um erro.

A velocidade só gera confiança quando existe segurança.

**Requisito candidato:**

> Operações de organização e manipulação em massa deverão, sempre que técnica e semanticamente apropriado, oferecer mecanismo de reversão, desfazer ou recuperação segura.

Isso não implica necessariamente um `Ctrl+Z` universal na primeira versão.

O requisito serve para evitar decisões arquiteturais que inviabilizem recuperação futura.

---

# 13. Layout — backlog lógico identificado

O benchmark reforça a necessidade futura de um domínio específico de apresentação.

Entidades/conceitos candidatos:

```text
Collection Layout
Page
Slot
Slot Assignment
Expected Card
Expected Card Variant
Grid Geometry
Page Label
Cover
Visual Element
Custom Ordering
Merged Slot
```

## Capacidades observadas

- páginas;
- navegação entre páginas;
- quantidade configurável;
- grid variável;
- labels;
- capa;
- ordem customizada;
- ordenação automática;
- slots vazios;
- slots planejados;
- cartas faltantes;
- slots mesclados;
- imagens customizadas;
- inserts;
- reorganização visual;
- visão geral de páginas.

**Decisão:** não incorporar automaticamente essas estruturas ao `collection-ldm.md`. Abrir bloco lógico específico de Layout quando apropriado.

---

# 14. Grid configurável

Foram observadas geometrias como:

- 2×2;
- 3×3;
- 4×3;
- 4×4;
- 4×5;
- 5×4.

## Insight

A geometria não deve ser hardcoded como pressuposto universal.

O futuro Layout deverá suportar diferentes formatos de página.

Isso é especialmente importante para:

- binders 3×3;
- binders 4×4;
- binders especiais;
- páginas temáticas;
- futuras categorias de colecionáveis.

---

# 15. Merged Slots e elementos visuais

O PkmnBindr suporta mesclar pockets em painéis maiores e utilizar imagens customizadas.

Isso permite:

- Jumbo;
- artes de página;
- separadores;
- inserts;
- composição visual;
- elementos decorativos.

## Insight MMKYU

Um Slot futuro não deve necessariamente representar apenas uma carta.

O Layout poderá precisar distinguir:

```text
CARD_SLOT
VISUAL_ELEMENT
MERGED_REGION
```

Essa hipótese deverá ser avaliada no momento da modelagem do Layout.

---

# 16. Storage Capacity — descoberta para domínio futuro

Durante a inclusão de um Set, o benchmark calcula a capacidade do binder.

Exemplo observado:

```text
Current capacity: 135
Adding: 198

Needs 63 more slots
```

A ferramenta oferece alternativas como:

- mudar grid;
- adicionar páginas.

## Insight MMKYU

Como o MMKYU possui Storage físico real, capacidade poderá ser uma propriedade importante de determinados Storage Containers.

Exemplo:

```text
Binder
capacity = 180 slots
occupied = 160
available = 20
```

Ao tentar alocar 295 Inventory Items:

```text
Inventory Items: 295
Available slots: 180
Deficit: 115
```

Possíveis ações:

- escolher outro Storage;
- dividir entre Containers;
- manter parte sem Storage;
- reorganizar.

## Atenção

Capacidade pode não fazer sentido da mesma forma para todos os tipos de Storage.

Binder possui slots definidos.

ETB/Storage Box pode ter capacidade estimada, configurável ou não controlada.

**Decisão:** registrar como requisito para futura modelagem de Storage; não alterar o modelo atual automaticamente.

---

# 17. Busca orientada ao objeto físico

A busca do benchmark aceita informações que o usuário consegue ler diretamente na carta, incluindo:

- nome;
- número;
- `025/185`;
- promo code;
- artista;
- outros identificadores.

A busca dentro do binder pode navegar até a página e destacar o slot.

No mobile, existe busca transversal entre binders.

## Insight MMKYU

Pergunta central:

> Estou segurando esta carta. Quanto esforço preciso fazer para encontrá-la no sistema?

Fluxo desejável:

```text
025/185
   ↓
Card
   ↓
Card Variants
   ↓
Inventory Items
   ↓
Collection
   ↓
Storage
   ↓
Layout / Page / Slot
```

## Métrica candidata de UX

**Time-to-answer: "Eu já tenho esta carta?"**

O MMKYU deverá responder em poucos segundos.

Idealmente:

```text
Você possui?          SIM — 3 cópias
Variants              Normal ×2 / Reverse ×1
Collection            ME2.5
Storage               Binder ME2.5
Master Set satisfeito SIM
Duplicata disponível  SIM — 1
```

Essa profundidade pode ser uma vantagem competitiva do MMKYU.

---

# 18. Digital → físico: placeholders

O benchmark permite exportar cartas faltantes e imprimir em tamanho físico real.

Isso permite inserir placeholders no binder físico.

## Insight MMKYU

A distinção Slot ≠ Inventory Item cria uma oportunidade clara.

Exemplo de placeholder:

```text
ME2.5 #125

[imagem]

FALTANTE

Reverse Holo
```

Quando a carta for adquirida:

1. o placeholder físico é removido;
2. o Inventory Item passa a ocupar o Slot lógico;
3. a Collection atualiza a completude.

## Oportunidade

Criar no futuro:

- placeholders físicos;
- want lists;
- listas de troca;
- checklists;
- QR codes;
- relatórios de faltantes.

Isso conecta a experiência digital à organização física da coleção.

---

# 19. Sharing ≠ Visibility

O modelo lógico atual possui:

```text
visibility
PRIVATE | PUBLIC
```

O benchmark demonstra uma camada de compartilhamento mais sofisticada:

- link read-only;
- visitante sem conta;
- pausar link;
- manter URL ao reativar;
- expiração;
- reset de URL;
- QR Code;
- busca pública opcional.

## Insight

`Collection.visibility` e `Share Link` podem ser conceitos diferentes.

Exemplo futuro:

```text
Collection
visibility = PRIVATE

Share Link
├── read_only = true
├── expires_at = ...
└── token = ...
```

## Casos de uso

- feira;
- negociação;
- vendedor;
- grupo de WhatsApp;
- mostrar Collection;
- criador de conteúdo;
- evento;
- loja.

**Impacto:** ponto para revisão futura da LDM-09, sem alterar a decisão aprovada neste momento.

---

# 20. PX-04 — Collection Portability

O benchmark oferece importação por CSV de outros trackers e exportação de dados.

Itens não reconhecidos podem ser preservados como placeholders.

## Problema estratégico

Um colecionador avançado pode pensar:

> Já tenho 8.000 cartas cadastradas em outro aplicativo. Não vou começar novamente.

Essa é uma barreira de aquisição relevante.

## Requisito candidato

> O MMKYU deverá tratar importação e exportação como mecanismos estratégicos de aquisição, confiança e redução do lock-in percebido.

Princípios:

- dados pertencem ao usuário;
- facilitar entrada;
- permitir saída;
- preservar informação não reconhecida quando possível;
- criar mecanismos de reconciliação posterior;
- evitar perda silenciosa.

Não é necessário suportar todos os concorrentes no lançamento.

A arquitetura de produto, entretanto, não deve inviabilizar portabilidade.

---

# 21. Mobile como contexto de uso

O benchmark destaca o cenário de loja/evento:

> Estou vendo uma carta. Preciso dela?

Isso demonstra que mobile não deve ser tratado apenas como responsividade.

É um contexto operacional diferente.

## Casos de uso prioritários mobile

- "Eu tenho esta carta?"
- "Qual variante tenho?"
- "Quantas cópias?"
- "Está faltando?"
- "Onde está armazenada?"
- "Está na Wishlist?"
- "É duplicata?"
- "Posso trocar?"
- "Qual Collection precisa dela?"

A experiência mobile deverá otimizar consultas rápidas e ações de baixa fricção.

---

# 22. Catálogo fresco como parte da experiência

O benchmark informa suporte a inglês e japonês e atualização rápida de novos sets.

## Insight MMKYU

A percepção de qualidade do produto dependerá também da velocidade com que lançamentos aparecem no catálogo.

Para colecionadores ativos:

```text
Lançamento físico
        ↓
Expectativa de disponibilidade digital imediata
```

Portanto, **catalog freshness** deve ser tratado como atributo de experiência, não apenas como processo administrativo.

---

# 23. Variantes e preços

O benchmark acompanha printing/variant específica e associa preço à variante selecionada.

Isso reforça a decisão do MMKYU de tratar Card Variant como elemento fundamental.

## Insight

Preço de mercado deve, quando futuramente suportado, respeitar a variante/printing efetivamente possuída.

Não deve existir a simplificação:

```text
Card → one market price
```

quando o mercado distingue:

```text
Card
├── Normal
├── Reverse
├── Master Ball
└── outras variantes
```

---

# 24. Ordenação automática + Custom Order

O benchmark oferece ordenação por diferentes critérios e também organização manual.

## Insight

O MMKYU deverá distinguir:

```text
Canonical Order
Automatic Presentation Order
Custom User Order
```

Exemplos de ordenação futura:

- número do Card Set;
- Pokédex;
- raridade;
- tipo;
- artista;
- preço;
- variante;
- customizada.

A ordem visual não deve alterar a ordem canônica do catálogo.

---

# 25. Drag & Drop e reorganização

O benchmark demonstra dois comportamentos relevantes:

- Swap;
- Push/Insert.

Também permite movimentação entre páginas.

## Insight

Manipulação direta reduz dramaticamente a fricção de reorganização.

No futuro Layout, a interação deve permitir reorganizar a apresentação sem alterar:

- ownership;
- Card Variant;
- Collection;
- Storage físico;

salvo quando o usuário explicitamente executar uma operação física correspondente.

---

# 26. Cloud, offline e multi-device

O benchmark comunica:

- edição local;
- uso offline;
- backup em nuvem;
- sincronização entre dispositivos.

## Insight estratégico

O MMKYU deve considerar confiança nos dados como parte central da proposta de valor.

Colecionadores podem acumular anos de informação patrimonial e histórica.

Mesmo que offline não seja prioridade inicial, os seguintes atributos são importantes:

- persistência confiável;
- backup;
- recuperação;
- sincronização;
- transparência de estado;
- proteção contra perda de dados.

---

# 27. UX de confirmação e consequências

Uma das melhores decisões observadas no wizard é explicar **o que acontecerá** antes de executar.

Exemplo observado:

```text
What will happen

Remove existing cards
Expand binder
Add cards
Add Reverse Holo parallels
Place parallels in selected order
```

## Diretriz MMKYU

Operações grandes devem parecer pequenas, mas **não opacas**.

O usuário deve conseguir responder antes de confirmar:

1. O que será criado?
2. O que será removido?
3. O que será alterado?
4. Onde ficará?
5. Qual será o impacto na completude?
6. Posso desfazer?
7. Existe algum conflito?

Velocidade e controle devem coexistir.

---

# 28. Requisitos candidatos consolidados

## PX-01 — Bulk Collection Onboarding
Permitir inicialização e declaração de posse em massa a partir de referências canônicas.

## PX-02 — Preview Before Bulk Mutation
Mostrar consequências antes de operações em massa relevantes.

## PX-03 — Recoverability
Permitir reversão/recuperação segura quando aplicável.

## PX-04 — Collection Portability
Tratar importação/exportação como mecanismo de aquisição, confiança e redução de lock-in.

## PX-05 — Exception-Driven Data Entry
O esforço de cadastro deve ser proporcional às exceções, e não ao tamanho total da Collection.

## PX-06 — Object-in-Hand Search
O usuário deve conseguir localizar rapidamente uma carta usando informações impressas no objeto físico.

## PX-07 — Digital/Physical Bridge
O produto deverá explorar conexões úteis entre Collection digital e organização física, incluindo placeholders, listas e localização.

## PX-08 — Bulk Operations as a Platform Capability
Operações em massa deverão ser uma capacidade transversal e consistente entre domínios.

> PX-05 a PX-08 são requisitos candidatos derivados deste benchmark e ainda deverão passar pelo processo normal de validação.

---

# 29. Backlog de decisões de modelagem identificado

O benchmark não deve alterar automaticamente o LDM atual.

Entretanto, foram identificados blocos futuros:

## Collection Presentation / Layout
- Collection Layout
- Page
- Slot
- Slot Assignment
- Expected Card / Variant
- Grid Geometry
- Page Label
- Cover
- Visual Element
- Merged Region
- Ordering

## Storage
- capacidade;
- ocupação;
- slots físicos;
- tipos de capacidade;
- divisão entre Containers.

## Sharing
- Share Link;
- expiração;
- pause/resume;
- reset;
- QR Code;
- read-only;
- eventual busca pública.

## Bulk Operations
- seleção;
- configuração;
- preview;
- confirmação;
- execução;
- tratamento de erro;
- recoverability.

## Import / Export
- formatos;
- reconciliação;
- placeholders;
- unmatched records;
- provenance.

## Search
- busca canônica;
- busca em Inventory;
- busca em Collections;
- busca em Storage;
- busca em Layout;
- busca transversal mobile.

---

# 30. O que não copiar

O benchmark é referência, não especificação.

Não devemos copiar automaticamente:

- estrutura de navegação;
- identidade visual;
- modelo de monetização;
- nomenclatura;
- limites de binder;
- grids específicos;
- dependências de fornecedores;
- regras de preço;
- arquitetura;
- definição Binder = Collection.

## Principal risco

Reduzir o MMKYU a um binder designer.

A proposta deve permanecer mais ampla:

> Uma plataforma profissional de gerenciamento do colecionismo Pokémon TCG, na qual o binder digital é uma experiência de interação — não o modelo inteiro do produto.

---

# 31. Vantagem competitiva potencial do MMKYU

O PkmnBindr demonstra excelente UX para binder.

O MMKYU pode combinar essa qualidade de interação com um modelo de domínio mais profundo.

Exemplo:

```text
Carta selecionada
      │
      ├── Canonical Card
      ├── Card Variant
      ├── Inventory Item
      ├── Owner
      ├── Collection
      ├── Completion Requirement
      ├── Storage
      ├── Page / Slot
      ├── Wishlist
      └── future market intelligence
```

Isso possibilita responder perguntas que um binder puramente visual não necessariamente consegue responder de forma integrada.

---

# 32. Princípio estratégico resultante

O principal aprendizado deste benchmark pode ser resumido em:

> **O MMKYU deve combinar profundidade de gestão com uma experiência que faça operações complexas parecerem simples.**

A sofisticação deve existir no modelo.

A simplicidade deve existir na interface.

O usuário não deve pagar, em esforço operacional, pelo fato de o MMKYU possuir um modelo mais rico.

---

# 33. Prioridades recomendadas decorrentes do benchmark

### P0 — Crítico para adoção
- Bulk Collection Onboarding;
- cadastro orientado por exceções;
- busca rápida;
- operações em massa com preview.

### P1 — Alto valor
- Layout de binder;
- Pages / Slots;
- missing placeholders;
- mobile quick check;
- importação de trackers;
- compartilhamento read-only.

### P2 — Diferenciação
- Storage capacity;
- impressão de placeholders;
- QR Code;
- recoverability avançada;
- custom covers;
- merged visual regions;
- inteligência transversal Collection + Inventory + Storage.

A priorização definitiva deverá ocorrer no roadmap de Produto, não neste benchmark.

---

# 34. Impacto no checkpoint atual de modelagem

O benchmark **não invalida** as decisões já aprovadas no modelo lógico de Collection.

Em particular, permanecem válidas as separações entre:

- Collection;
- Inventory Item;
- Card Variant;
- Storage;
- Completion Policy;
- Adopted Scope;
- Ownership.

As descobertas devem alimentar decisões futuras, especialmente:

- Layout;
- Storage;
- Sharing;
- Bulk Operations;
- Search;
- Import/Export.

O fluxo de modelagem de Collection pode ser retomado do ponto anteriormente definido após o registro deste benchmark.

---

# 35. Fontes públicas consultadas

- PkmnBindr — página principal: https://www.pkmnbindr.com/
- Help — Search tricks: https://pkmnbindr.com/help/search-tips
- Help — Card variants and prices: https://pkmnbindr.com/help/card-variants-and-prices
- Help — Sharing your binder: https://pkmnbindr.com/help/share-your-binder
- Help — Printing and PDF export: https://pkmnbindr.com/help/printing-and-pdf-export

Também foram utilizadas como evidência as capturas de tela fornecidas durante a análise, especialmente dos fluxos:

- criação/visualização de binder;
- grid e páginas;
- card picker;
- importação de Card Set;
- seleção de variantes;
- cálculo de capacidade;
- review & confirm;
- visualização de cartas e preços.

---

# 36. Conclusão

O benchmark confirmou que **velocidade, praticidade e manipulação visual** devem ser atributos centrais da experiência do MMKYU.

A principal implicação estratégica é clara:

> O modelo profundo do MMKYU não pode resultar em uma experiência burocrática.

O catálogo canônico deve eliminar trabalho repetitivo.

Bulk Operations devem reduzir centenas de ações a poucas decisões.

Layouts devem oferecer liberdade sem comprometer integridade.

Inventory, Ownership e Storage devem permanecer rigorosos sem aparecer ao usuário como complexidade desnecessária.

O objetivo não é reproduzir o PkmnBindr.

O objetivo é alcançar a mesma sensação de fluidez em uma plataforma significativamente mais completa.

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Documento produzido no repositório de modelagem paralelo `mimikyu-modelagem-de-dados` (15/08/2026). |
| 1.1 | Incorporado a `project-mimikyu` (2026-08-28, pedido explícito de Fabrício) em `docs/domain-modeling/collections/`. Nenhum conteúdo alterado — apenas cabeçalho e nota de incorporação adicionados. |
