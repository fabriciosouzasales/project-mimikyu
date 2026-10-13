# Pokédex P3d — Conteúdo Editorial pt-BR

| Campo | Valor |
|-------|-------|
| **Status** | Piloto **APROVADO** (2026-10-12) para publicação controlada de homologação; Query 6136 e validação 6847 em **PROPOSTA** — nada gravado no LIVE. Experiência bilíngue implementada e homologada visualmente (local). |
| **Data** | 2026-10-12 |
| **Escopo** | Classificação (GENUS) e descrição (FLAVOR) em pt-BR, autorais do MMKYU, para as 1.025 espécies. Piloto: 10 espécies. |
| **Arquivos** | este README · `pilot-pt-BR.json` (piloto aprovado, revisão 4, com md5 de cada texto) · `6136_publish_pokedex_editorial_ptbr_pilot.sql` (publicação, PROPOSTA) · `6847_validate_pokedex_editorial_ptbr_pilot.sql` (validação pós-publicação, só leitura) |

## Decisões aprovadas (2026-10-12)

1. Reutilizar `pokemon_species_text` (origin `MMKYU_EDITORIAL`), sem tabelas novas.
2. Textos originais em inglês e sua proveniência preservados.
3. pt-BR publicado como conteúdo editorial MMKYU, nunca como tradução oficial.
4. Rascunhos JSON versionados com estados `PROPOSTO` → `APROVADO`.
5. Terminologia consistente via glossário editorial.
6. Região da geração ≠ referências regionais das histórias.
7. Revisão de qualidade antes de publicar; avaliação de direitos antes de exploração comercial.

## Diagnóstico da estrutura (resumo)

- `pokemon_species_text`: chave `(espécie, text_kind, language_code, origin)`; `origin` SOURCE/MMKYU_EDITORIAL; `rights_status` inclui MMKYU_EDITORIAL; idioma BCP 47 livre. LIVE: 2.050 linhas, todas SOURCE `en` (1.025 GENUS + 1.025 FLAVOR).
- Reimportação (`admin_record_pokemon_species_profile`) só regrava SOURCE; editorial preservado.
- `get_pokedex_species_detail(n, p_language)` escolhe por campo: idioma pedido oficial > idioma pedido editorial > `en` oficial > `en` editorial, com idioma efetivo, flag de oficial e versão de origem.
- **Lacuna bloqueante:** a ficha não identifica texto editorial pt-BR (sem nota). Resolvida pela proposta da seção 4.

---

## 1. Guia editorial v0.2

**Propósito.** O texto complementa a ficha, não a repete. Número, geração, região, tipos, altura, peso e status (lendário/mítico) já estão visíveis — só entram no texto quando são o próprio tema (ex.: a combinação de tipos de Volcanion).

**Voz.** Clara, envolvente e confiável: um colecionador experiente contando o que torna a espécie memorável. Terceira pessoa, presente do indicativo, sem "você", sem exclamações, sem gíria, sem humor forçado. Português brasileiro natural — ler em voz alta antes de aprovar.

**Foco.** Priorizar o traço mais marcante, uma curiosidade ou a identidade da espécie. Abrir pelo que é interessante, não por dados de catálogo.

**Tamanho (referência flexível).** Em torno de 2 frases e 180–320 caracteres. Textos mais curtos são aceitos quando a base factual é pequena; mais longos só se cada frase acrescentar fato novo. Nunca um bloco denso.

**Fatos.** Somente: (a) campos do banco; (b) a descrição oficial armazenada (com versão). Não preencher lacunas, não especular, não trazer fatos de anime, filmes, outros jogos ou memória geral se não estiverem na base. Nada de quantidades, rankings ou exclusividades ("único", "o mais") — envelhecem e raramente são verificáveis.

**Fato × relato × mitologia.** Lendas e crenças sempre enquadradas ("Na mitologia de Hisui…", "Nas lendas…"). Relatos individuais atribuídos a quem relatou ("um pesquisador registrou…"), nunca convertidos em verdade geral. Leituras editoriais leves (imagens, metáforas, reflexões) são permitidas e registradas em `editorial_interpretation` no rascunho.

**Originalidade.** A descrição oficial é fonte de fatos, não de frases: nada de tradução frase a frase, preservar a ordem de ideias só quando não houver alternativa, não reaproveitar imagens ou expressões distintivas do original. Quando o fato central for único, a originalidade vem do enquadramento (abertura, imagem, consequência).

**Classificação.** Sentido da classificação oficial em inglês em português natural: "Pokémon " + substantivo ou locução curta, sem artigo, compostos com hífen, maiúscula só no início. Alternativas registradas no glossário.

**Autoria.** Toda linha: `origin = MMKYU_EDITORIAL`, `rights_status = MMKYU_EDITORIAL`, `language_code = pt-BR`. Na ficha: "Texto editorial MMKYU · Português brasileiro". Nunca "tradução" nem "oficial".

**Checklist de aprovação (por entrada).**
1. Cada fato listado em `facts` com fonte ([DB] ou [EN versão]).
2. Toda interpretação listada em `editorial_interpretation`.
3. Não repete dados da ficha sem motivo.
4. Nenhuma frase espelha o original.
5. Mitologia/relatos enquadrados.
6. Termos conforme glossário.
7. Leitura natural em voz alta.
8. Aprovação explícita de Fabrício → `status: APROVADO`.

---

## 2. Dez textos revisados (v0.2, refinamento final de 2026-10-12)

**Estado:** todas as entradas em `PROPOSTO` até a aprovação final para publicação. Pendências registradas:
- **Classificações:** a correspondência com a terminologia brasileira (ex.: TCG Brasil) ainda não foi verificada.
- **Termo provisório:** "Equipe Plasma" foi adotado provisoriamente; a conferência terminológica está pendente.
- **Propriedade intelectual:** Bulbasaur e Pecharunt exigem avaliação antes de qualquer uso comercial.

**Refinamentos desta rodada:**
- **Mewtwo:** o encerramento interpretativo foi retirado.
- **Unown:** o relato particular do pesquisador foi retirado.
- **Arceus e Sprigatito:** os textos curtos foram mantidos.

| Nº | Espécie | Classificação | Descrição | Caract. |
|----|---------|---------------|-----------|---------|
| 0001 | Bulbasaur | Pokémon Semente | A semente nas costas de Bulbasaur não é enfeite: é a despensa que sustenta seu crescimento. Enquanto é jovem, ele recorre aos nutrientes guardados ali — um vínculo com o mundo das plantas que acompanha a espécie desde cedo. | 223 |
| 0025 | Pikachu | Pokémon Rato | As bochechas de Pikachu funcionam como pequenas baterias, onde ele guarda a eletricidade que produz. Engenhoso, encontrou um uso doméstico para esse poder: com um choque certeiro, tosta frutos duros antes de comê-los. | 217 |
| 0150 | Mewtwo | Pokémon Genético | Mewtwo compartilha com Mew quase todo o seu DNA, mas o parentesco para por aí: no porte e, sobretudo, no temperamento, os dois são profundamente diferentes. | 156 |
| 0201 | Unown | Pokémon Símbolo | Unown chama atenção pelo formato incomum: seus corpos lembram caracteres de escrita, e a espécie se apresenta em muitas formas diferentes. | 138 |
| 0493 | Arceus | Pokémon Alfa | Na mitologia de Hisui, Arceus está acima de tudo: é tido como o criador de todas as coisas e como a fonte de uma luz celeste que guia e protege os Pokémon da região. | 165 |
| 0649 | Genesect | Pokémon Paleozoico | Em Genesect, passado remoto e tecnologia se encontram: a espécie remonta a cerca de 300 milhões de anos, mas foi alterada pela Equipe Plasma. O canhão que carrega nas costas é obra dessa intervenção, não da natureza. | 216 |
| 0721 | Volcanion | Pokémon Vapor | Volcanion reúne no mesmo corpo fogo e água, duas forças que costumam se anular, e transforma esse encontro em vapor. A pressão é liberada pelos braços que tem nas costas, com potência para arrasar uma montanha. | 210 |
| 0905 | Enamorus | Pokémon Amor-Ódio | Nas lendas de Hisui, Enamorus é o mensageiro da primavera: quando atravessa o mar e chega à região, o inverno rigoroso termina. As mesmas histórias atribuem ao seu afeto o despertar de vida nova pela terra. | 206 |
| 0906 | Sprigatito | Pokémon Gato-Planta | O trunfo de Sprigatito é discreto: o aroma adocicado que o corpo exala, capaz de encantar quem estiver por perto. Sob o sol, o perfume fica mais intenso — e o encanto também. | 174 |
| 1025 | Pecharunt | Pokémon Dominação | Por trás da aparência de fruta, Pecharunt guarda um perigo: a carapaça em forma de pêssego é um reservatório de veneno potente. É desse estoque que saem os mochis envenenados que ele prepara para oferecer a pessoas e Pokémon. | 225 |

**Principais mudanças em relação à v0.1:** saíram as aberturas de catálogo (número, tipos, medidas, status); Unown atribui o relato a um pesquisador; Volcanion perdeu a afirmação de exclusividade; Pecharunt mudou de classificação ("Subjugação" → "Dominação") e de abertura; Arceus e Enamorus enquadram todo o conteúdo como mitologia/lenda.

**Pontos de revisão por espécie** (detalhe com fundamentos em `pilot-pt-BR.json`):

- **Bulbasaur:** Redação revisada preservada; Fato central é o mesmo da descrição oficial: avaliação de propriedade intelectual obrigatória antes de uso comercial.
- **Pikachu:** 'tostar' para 'roasts' — conferir naturalidade; Não usa fatos de anime/franquia sem base no banco.
- **Mewtwo:** Encerramento interpretativo removido (refinamento 2026-10-12); Medidas e status lendário fora do texto (já estão na ficha).
- **Unown:** Relato particular do pesquisador removido (refinamento 2026-10-12); ficam só formato incomum, semelhança com escrita e muitas formas; Não cita a quantidade de formas (fora da base); Texto curto por falta de base factual — aceito pela regra flexível.
- **Arceus:** Todo o conteúdo enquadrado como mitologia; Ficha mostra Sinnoh (geração); texto cita Hisui (história); Texto curto mantido (decisão 2026-10-12: não alongar).
- **Genesect:** 'Equipe Plasma' adotada provisoriamente; conferência terminológica pendente; 'cerca de' suaviza o número exato da fonte.
- **Volcanion:** Afirmação de exclusividade removida; Cita os tipos porque são o próprio tema do texto (exceção justificada à regra de não repetir a ficha).
- **Enamorus:** Ficha mostra Galar (geração); texto cita Hisui (história); Classificação: hífen ou 'Amor e Ódio'.
- **Sprigatito:** Fato 'inicial de Paldea' é conhecido mas não está na base — não usado; Texto curto mantido (decisão 2026-10-12: não alongar).
- **Pecharunt:** Redação revisada preservada; classificação 'Dominação' mantida; Fato central é o mesmo da fonte: avaliação de propriedade intelectual obrigatória antes de uso comercial; 'mochis' conforme glossário.

---

## 3. Glossário inicial (piloto)

| Termo | Uso MMKYU | Observação |
|-------|-----------|------------|
| Pokémon | Invariável, com acento, também no plural | "a pessoas e Pokémon" |
| Pokédex Nacional | Maiúsculas | Nome da seção no produto |
| Nomes de espécie | Nome oficial em inglês (`canonical_name`) | Iguais no Brasil |
| Regiões | Sem tradução: Kanto, Johto, Sinnoh, Unova, Kalos, Galar, Hisui, Paldea | "região de Hisui" |
| Tipos | Rótulos de `pokemon_type`: Planta, Venenoso, Elétrico, Psíquico, Normal, Inseto, Aço, Fogo, Água, Fada, Voador, Fantasma… | Mesmos rótulos dos chips |
| Lendário / Mítico | Minúsculas no texto | Só quando for o tema; já aparece na ficha |
| Classificação | Termo do produto para *genus* (Seed Pokémon → Pokémon Semente) | Nunca "categoria oficial" |
| Equipe Plasma | Para *Team Plasma* | **Confirmar** se há forma consagrada no Brasil |
| mochi / mochis | Minúsculo, sem itálico; plural "mochis" | Doce japonês |
| DNA | Sigla mantida | — |
| Classificações do piloto | Semente · Rato · Genético · Símbolo · Alfa · Paleozoico · Vapor · Amor-Ódio (alt. Amor e Ódio) · Gato-Planta (alt. Gato de Planta) · Dominação (alt. Subjugação) | Ver R2: possível terminologia oficial pt-BR (TCG) |

---

## 4. Proposta mínima — identificação e alternância de idiomas na ficha

**Os dois idiomas sem SQL novo: sim.** `get_pokedex_species_detail(n, 'en')` devolve a classificação e a descrição oficiais em inglês (a ordenação prioriza `en` + SOURCE), com versão de origem. Basta uma segunda chamada da mesma função, já autorizada para `authenticated`. Nenhuma alteração na 6133 ou em contrato.

**Dados (servidor).**
- `app/pokedex/[numero]/page.tsx` passa a chamar, em paralelo com a leitura atual (pt-BR), `get_pokedex_species_detail(n, 'en')`. É a mesma função, uma espécie, custo marginal, sem cascata.
- Se a chamada `en` falhar, a página segue só com o pt-BR (degradação silenciosa, com log).
- Texto original considerado presente quando a resposta pt-BR veio editorial (`description_is_official = false` e `description_language = 'pt-BR'`) e a resposta `en` trouxe texto oficial.

**Interface (dentro do bloco de descrição da P3b, sem nova seção).**
- Quando há texto editorial pt-BR e original em inglês, um controle segmentado discreto **Português | English** fica acima da descrição, com o estilo de controle do Design System e o dourado só no estado ativo. Português é o padrão.
- Português mostra a descrição editorial e a nota "✎ Texto editorial MMKYU · Português brasileiro".
- English mostra a descrição oficial e a nota "Descrição oficial em inglês · *Pokémon Shield*" (versão de origem). Opcionalmente, mostra também a classificação original (*Seed Pokémon*) na nota.
- Sem texto editorial, a ficha fica como hoje (inglês com a nota existente) e não aparece controle nenhum.
- A classificação do cabeçalho da ficha não muda com a alternância: continua pt-BR editorial, se existir, e a nota do modo Português cobre os dois textos ("Classificação e descrição: texto editorial MMKYU").

**Acessibilidade.**
- Grupo com `role="group"` e `aria-label="Idioma da descrição"`, dois `<button aria-pressed>`.
- O parágrafo leva `lang="pt-BR"` ou `lang="en"` conforme o texto, e a troca é anunciada pela região da nota (`aria-live="polite"`).
- Foco visível com o anel dourado e alvos de pelo menos 40 px.
- Os dois textos vêm renderizados pelo servidor: o inativo fica com `hidden`, a troca é instantânea e não depende de rede.

**Implementação estimada.**
- Uma ilha cliente pequena (`description-language-toggle.tsx`, só `useState`).
- Ajuste de `buildSourceNote` para o caso editorial (corrige a lacuna bloqueante) e leitura extra em `lib/pokedex/detail.ts`.
- Testes unitários da regra de nota.
- Nada muda na Pokédex Nacional. A escolha do idioma não é persistida por enquanto; dá para guardar em `localStorage` depois, se fizer sentido.

---

**Implementação local (2026-10-12, não publicada):**
- `lib/pokedex/description-presentation.ts`: regra pura dos modos — sem descrição; único, com a nota da P3b preservada; e bilíngue.
- `lib/pokedex/detail.ts` → `getPokedexSpeciesOriginalText`: segunda leitura da mesma função com `p_language = 'en'`. Só é disparada pela página quando a ficha veio editorial pt-BR e roda em paralelo com as demais leituras.
- `components/pokedex/detail/species-description-bilingual.tsx`: componente cliente com o controle "Português | English".
- Estilos em `species-detail.module.css`.
- Testes em `description-presentation.test.ts` e `detail.test.ts`.
- Nenhum SQL e nenhuma mudança na 6133.

## 5. Fluxo de aprovação e publicação por lotes

1. **Insumos.** Uma leitura de fatos por lote, só leitura: tipos, flags, classificação e descrição `en` com versão.
2. **Rascunho.** Textos gerados com IA restrita aos insumos e ao guia, no JSON do lote (`status: PROPOSTO`, com `facts`, `editorial_interpretation` e `review_points`). Lotes de 50 a 100 espécies.
3. **Verificação automática.** Faixa de tamanho, termos do glossário, números que não estejam nos fatos, palavras proibidas ("único", "oficial", "tradução") e frases repetidas entre entradas do lote.
4. **Revisão humana.** Checklist da seção 1 entrada por entrada. Aprovadas viram `APROVADO`; reprovadas voltam com nota. O commit do JSON registra a aprovação.
5. **Gravação.** Uma Query do lote (padrão STD-001), gerada a partir do JSON, só com entradas `APROVADO`:
   - faz `INSERT … ON CONFLICT … DO UPDATE` com `origin` e `rights_status` fixos em `MMKYU_EDITORIAL`;
   - é idempotente e checa contagem antes e depois;
   - é executada por Fabrício.
6. **Validação.** Query só de leitura comparando o LIVE com o JSON (contagem, `md5` do conteúdo) e conferência visual de 3 fichas do lote.
7. **Registro.** Uma linha em `docs/log.md` por lote.
8. **Correções.** Editar o JSON, reaprovar e regravar a mesma linha. O SOURCE nunca é tocado.
9. **Remoção.** `DELETE` restrito a `origin = 'MMKYU_EDITORIAL'` da espécie; a ficha volta ao inglês.

---

## 6. Bloqueios reais para publicar o piloto

| # | Bloqueio | Tipo | Resolução |
|---|----------|------|-----------|
| B1 | A ficha não identifica texto editorial pt-BR | Técnico (frontend) | Implementar a seção 4 antes de gravar (ou na mesma rodada). |
| B2 | Aprovação editorial dos 10 textos e classificações (incluindo as alternativas) | Editorial | Fabrício marca `APROVADO`. |
| B3 | Glossário: "Equipe Plasma" e possível terminologia oficial pt-BR das classificações (TCG Brasil) | Editorial / IP | Decidir a política; o piloto pode sair com a decisão registrada. |
| B4 | Query de gravação e validação do piloto | Técnico | A preparar depois de B2, executada por Fabrício. |
| — | Avaliação jurídica | Pré-comercialização | Não bloqueia o piloto interno; bloqueia exploração comercial. |

**Efeito colateral a aceitar:** durante a publicação em lotes, as espécies sem texto editorial continuam em inglês. É consistente com a regra de prioridade, mas mistura idiomas entre fichas até a conclusão.

## Riscos (mantidos da v0.1)

- **R1 Propriedade intelectual.** Nomes, classificações e lore pertencem a Nintendo/Creatures/GAME FREAK/TPC. Texto original reduz o risco de obra derivada, mas não o elimina; paráfrase próxima não o remove.
- **R2 Classificações.** São quase traduções de um termo oficial curto. Se existir terminologia oficial em português, divergir pode confundir e copiar levanta R1.
- **R3 Base factual estreita.** Há uma única descrição oficial por espécie, o que aumenta o risco de paráfrase próxima. Textos mais ricos exigem importar mais versões numa rodada própria.
- **R4 Afirmações que envelhecem.** Superlativos e exclusividades ficam proibidos pelo guia v0.2.
- **R5 Escala com IA.** Mitigado pelos passos 3 e 4 da seção 5.

---

## Publicação controlada do piloto (Query 6136 + validação 6847) — PROPOSTA

**Estado do piloto:** as 10 entradas estão `APROVADO` (revisão 4 do JSON), com o rótulo de publicação "Piloto editorial MMKYU". Os textos são os da v0.2 refinada, incluindo Mewtwo e Unown revisados, e seguem o guia v0.2. Ressalvas mantidas no JSON:
- classificações e "Equipe Plasma" pendentes de confirmação terminológica;
- Bulbasaur e Pecharunt exigem avaliação de propriedade intelectual antes de uso comercial;
- nenhuma atribuição de oficialidade.

**6136 (escrita, transação única):**
- **Payload:** os 20 textos aprovados (10 espécies × GENUS + FLAVOR) numa tabela temporária, num único bloco com falha integral.
- **Pré-condições:** 10 espécies ativas, com perfil IMPORTED e com os textos oficiais `en`; conteúdo entre 1 e 2.000 caracteres.
- **Escrita:** `INSERT … ON CONFLICT ON CONSTRAINT uq_pokemon_species_text DO UPDATE`.
  - A chave inclui `origin`, então só linhas `MMKYU_EDITORIAL` pt-BR podem ser criadas ou atualizadas; textos `SOURCE` nunca são alvo.
  - Só atualiza se o conteúdo mudou, o que torna a operação idempotente.
- **Pós-condições na mesma transação:**
  - 20 linhas editoriais do piloto, com conteúdo idêntico ao payload;
  - `rights_status`, `source_version`, `asset_source_id` e `retrieved_at` corretos;
  - hash do conjunto `SOURCE` (2.050 linhas) igual ao de antes;
  - linhas editoriais de outras espécies inalteradas.
- **Falha:** qualquer violação desfaz tudo.
- **O que não cria:** função, tabela, coluna ou grant. Nenhuma alteração na 6133 nem em migrations.

**6847 (só leitura, BEGIN/ROLLBACK):** confere as linhas gravadas e a leitura da ficha.
- Exatamente 20 linhas editoriais no banco, todas das 10 espécies, uma GENUS e uma FLAVOR por espécie.
- Idioma pt-BR, direitos `MMKYU_EDITORIAL` e nenhuma proveniência de fonte.
- md5 de cada texto igual ao do JSON aprovado.
- Textos oficiais preservados: 2.050 linhas com hash igual à linha de base `ca8e9c87244160063971bd1a9f808b78`, medida no LIVE em 2026-10-12, timestamps em UTC.
- Leitura da ficha com sessão simulada:
  - #1 em pt-BR devolve o editorial;
  - #1 em `en` devolve o oficial com a versão;
  - #4 (fora do piloto) continua com o oficial em `en`.

**Conferência só de leitura feita em 2026-10-12** (nada gravado): o payload casa com as 10 espécies ativas com perfil IMPORTED. São 20 textos, com md5 do Postgres igual ao do JSON e no máximo 225 caracteres. Existem 20 textos oficiais `en` dessas espécies e 0 linhas editoriais no banco.

**Ordem de execução (após autorização):** 6136 → 6847 (`6847 PASS`) → homologação no navegador em `/pokedex/1` (Bulbasaur). Na ficha, conferir:
- alternância Português | English e foco por teclado;
- desktop e celular, temas claro e escuro;
- notas de proveniência nos dois idiomas.

**Rollback:** `DELETE` só das linhas `MMKYU_EDITORIAL` pt-BR das 10 espécies (comando no rodapé da 6136). As fichas voltam ao inglês oficial automaticamente, sem mudança de código.

**Promoção:** depois de executada e validada, a 6136 entra no repositório como dado editorial versionado, com destino canônico a decidir (por exemplo `database/seeds/`), já que não é schema.
