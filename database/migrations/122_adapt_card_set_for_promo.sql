/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 122 - Adapt Card Set for Promo
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Status......: MIGRATION (reclassificação retroativa — ver STD-001, Seção 10,
               Princípio da Fonte Canônica). Esta migration alterou um banco
               que já possuía a tabela card_set (criada por 120 v1.0). Não é
               mais necessária em uma instalação nova: a Query canônica
               120 v2.0 (ver database/schema/120_create_card_set_table.sql)
               já nasce com suporte nativo a PROMO. Preservada apenas como
               registro histórico de como o suporte a PROMO foi introduzido
               no banco atual.
Descrição...:
Adapta a entidade card_set para suportar séries promocionais Black Star
como Card Sets do tipo PROMO.
Regras de Negócio:
- O tipo do Card Set pode ser REGULAR, SPECIAL ou PROMO.
- O Card Set promocional ocupa sempre a primeira posição da Expansion.
- Os demais Card Sets devem ser deslocados uma posição.
- Um Card Set PROMO deve possuir base_set_size igual a total_set_size.
- Os dados existentes devem ser preservados.
- A migration deve ser executada de forma transacional.
Pendência sinalizada (ver ADR-015 e docs/05-modelo-de-dados.md, seção Set):
esta migration NÃO cria um índice único parcial para impedir mais de uma
série PROMO por Expansion. A regra é hoje verificada apenas pela Query de
validação 920, não impedida na escrita.
===============================================================================
*/

BEGIN;

------------------------------------------------------------------------------
-- 1. Remove a constraint atual de tipo
------------------------------------------------------------------------------
ALTER TABLE public.card_set
DROP CONSTRAINT ck_card_set_type;

------------------------------------------------------------------------------
-- 2. Cria a nova constraint incluindo PROMO
------------------------------------------------------------------------------
ALTER TABLE public.card_set
ADD CONSTRAINT ck_card_set_type
CHECK (set_type IN ('REGULAR', 'SPECIAL', 'PROMO'));

------------------------------------------------------------------------------
-- 3. Desloca temporariamente as ordens atuais para evitar conflito
------------------------------------------------------------------------------
UPDATE public.card_set
SET release_order = release_order + 100
WHERE expansion_id = (
    SELECT expansion.id
    FROM public.expansion
    INNER JOIN public.game
        ON game.id = expansion.game_id
    WHERE game.code = 'POKEMON'
      AND expansion.code = 'ME'
);

------------------------------------------------------------------------------
-- 4. Define as novas ordens editoriais
------------------------------------------------------------------------------
UPDATE public.card_set
SET release_order =
    CASE code
        WHEN 'ME1'   THEN 2
        WHEN 'ME2'   THEN 3
        WHEN 'ME2.5' THEN 4
        WHEN 'ME3'   THEN 5
        WHEN 'ME4'   THEN 6
    END
WHERE expansion_id = (
    SELECT expansion.id
    FROM public.expansion
    INNER JOIN public.game
        ON game.id = expansion.game_id
    WHERE game.code = 'POKEMON'
      AND expansion.code = 'ME'
)
AND code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4');

------------------------------------------------------------------------------
-- 5. Garante igualdade entre base e total para Sets promocionais
------------------------------------------------------------------------------
ALTER TABLE public.card_set
ADD CONSTRAINT ck_card_set_promo_size
CHECK (
    set_type <> 'PROMO'
    OR base_set_size = total_set_size
);

COMMIT;
