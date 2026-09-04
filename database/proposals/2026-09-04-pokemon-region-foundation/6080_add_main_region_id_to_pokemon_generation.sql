/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6080 - Add main_region_id to Pokemon Generation
Versão......: 1.1 (revisão: FK explícita ON UPDATE RESTRICT ON DELETE
               RESTRICT — achado de auditoria externa, GATE 4)
Status......: PROPOSTO (staging — NÃO executado)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-REGION-FOUNDATION-
               PHYSICAL-STAGING-01; revisado em 2026-09-04 via
               POKEMON-REGION-FOUNDATION-PHYSICAL-STAGING-REVISION-01)

Descrição resumida:
Incremento físico sobre pokemon_generation (Query 6000, já CONFIRMADO
EXECUTADO): adiciona main_region_id, a FK que resolve a Região
principal de cada Generation. Não reescreve 6000/6001 — é uma Query
nova e independente, mesmo princípio já usado em Query 6701 (correção
nunca é edição retroativa de histórico físico já aplicado).

Descrição:
Decisão congelada em POKEMON-REGION-FOUNDATION-PHYSICAL-MODELING-01:
cardinalidade Generation → Region é N:1 — cada Generation tem
exatamente uma Main Region, mas uma Region pode ser Main Region de
0..N Generations (a unicidade reversa observada no dataset atual da
PokéAPI — hoje aparentemente 1:1 — NÃO é invariante de domínio, é
padrão observado). Por isso:

- NÃO existe UNIQUE em main_region_id.
- NÃO existe índice dedicado nesta rodada — volume esperado é da ordem
  de dezenas de linhas em pokemon_generation (hoje zero, 9 Generations
  esperadas na carga futura), mesmo raciocínio já usado para não
  indexar pokemon_generation/pokedex (tabelas pequenas, sem índice além
  de PK/UNIQUE — confirmado por consulta real a pg_indexes nesta mesma
  rodada de modelagem). Caso o volume real divirja desta expectativa,
  um índice deve ser criado como Query nova, proporcional ao padrão de
  acesso real observado — nunca antecipado especulativamente aqui.

Governança (decisão congelada em POKEMON-REGION-FOUNDATION-PHYSICAL-
MODELING-01, ponto D): main_region_id é dado estrutural sourced e NÃO
deve mudar silenciosamente, mas correção editorial futura pode ser
necessária. A regra mais coerente com o mecanismo de sourcing/
reconciliação já desenhado (Rounds 1-4, hoje SUSPENSO) é: qualquer
mudança de main_region_id observada durante uma futura reconciliação
de sourcing deve ser classificada como DIVERGENT (nunca aplicada
silenciosamente pelo pipeline automático) — a proteção contra mudança
não intencional vive na camada de sourcing/reconciliação, não em um
trigger de banco. Por isso, deliberadamente:

- main_region_id NÃO é adicionado à lista de campos protegidos por
  govern_pokemon_generation() (Query 6001, já CONFIRMADO EXECUTADO —
  não reescrita nesta rodada). Ele permanece UPDATE-ável a nível de
  banco, da mesma forma que canonical_name/is_active já são.
- Esta ausência de trigger de imutabilidade NÃO autoriza UPDATE manual
  direto em main_region_id fora do fluxo de sourcing/reconciliação ou
  de correção editorial administrativa deliberada e documentada — é
  uma decisão de onde a proteção vive, não uma liberação de uso.

Regras de Negócio:
- main_region_id é NOT NULL — toda Generation deve ter exatamente uma
  Main Region resolvida no momento da inserção (mesmo requisito que o
  futuro sourcing já precisa satisfazer para cada Generation
  descoberta).
- ON DELETE RESTRICT — uma Region referenciada como Main Region de ao
  menos uma Generation não pode ser excluída.
- ON UPDATE RESTRICT — declarado explicitamente nesta revisão (achado
  de auditoria externa, GATE 4, POKEMON-REGION-FOUNDATION-PHYSICAL-
  STAGING-REVISION-01). Ambas as pontas (id de pokemon_generation e id
  de pokemon_region) já são imutáveis por trigger de governança em
  ambas as tabelas, o que torna o comportamento observável de ON
  UPDATE RESTRICT idêntico ao de deixar a cláusula implícita (NO
  ACTION) — mas a versão anterior desta Query (1.0) confiava
  silenciosamente nessa imutabilidade de aplicação para nunca reescrita
  retroativa de pokemon_region.id, em vez de expressar a garantia como
  contrato físico da própria FK. Declarar ON UPDATE RESTRICT
  explicitamente remove essa dependência implícita: a garantia passa a
  valer mesmo que a proteção de trigger de pokemon_region (Query 6061)
  seja alterada ou removida no futuro, sem depender de nenhuma outra
  Query para se manter verdadeira — defesa em profundidade, mesmo
  princípio já aplicado ao REVOKE de least privilege (Query 2147)
  embutido em 6060/6070.
- Adicionada sem DEFAULT: seguro porque pokemon_generation está com
  zero linhas hoje (confirmado por consulta real ao banco nesta mesma
  rodada de modelagem — módulo CLOSED/COMMITTED/PUSHED, sourcing ainda
  não executado). Caso esta premissa tenha mudado no momento da
  execução real (linhas já existentes em pokemon_generation), o ALTER
  abaixo falhará por NOT NULL — comportamento correto e esperado
  (nunca deve inserir um valor arbitrário/backfill silencioso; se isso
  ocorrer, sinalizar a divergência explicitamente antes de prosseguir,
  em vez de adaptar o script).

Fora de Escopo (decisão explícita desta rodada):
- Qualquer alteração em govern_pokemon_generation() (Query 6001) — não
  reescrita.
- Sourcing real, preenchimento de main_region_id via PokéAPI —
  permanece SUSPENSO.

Pré-requisitos:
- Query 6000 - Create Pokemon Generation Table (CONFIRMADO EXECUTADO).
- Query 6001 - Pokemon Generation Triggers (CONFIRMADO EXECUTADO).
- Query 6060 - Create Pokemon Region Table (desta mesma pasta de
  staging).
===============================================================================
*/

BEGIN;

ALTER TABLE public.pokemon_generation
    ADD COLUMN main_region_id UUID NOT NULL
        REFERENCES public.pokemon_region (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT;

COMMENT ON COLUMN public.pokemon_generation.main_region_id IS
    'Região principal desta Generation (N:1 — uma Region pode ser Main Region de 0..N Generations; unicidade reversa NÃO é invariante de domínio, decisão congelada POKEMON-REGION-FOUNDATION-PHYSICAL-MODELING-01). ON UPDATE RESTRICT ON DELETE RESTRICT, ambos declarados explicitamente na FK. Dado estrutural sourced: mudança silenciosa não é esperada, mas o campo permanece corrigível a nível de banco (UPDATE direto do valor de main_region_id em pokemon_generation, reatribuindo para outra Region, continua permitido) — a proteção contra divergência não intencional vive na camada de sourcing/reconciliação (classificação DIVERGENT), não em trigger de imutabilidade. NÃO adicionado a govern_pokemon_generation() (Query 6001) nesta rodada.';

COMMIT;

-- ================================================================
-- PROPOSTO — staging, NÃO executado. Ver nota de status em 6060.
-- Pré-condição verificada nesta rodada de modelagem (não nesta
-- execução): pokemon_generation com zero linhas — a ausência de
-- DEFAULT depende desta premissa permanecer verdadeira no momento da
-- execução real.
-- ================================================================
