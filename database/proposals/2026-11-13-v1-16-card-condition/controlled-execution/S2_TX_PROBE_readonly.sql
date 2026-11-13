/*
================================================================
V1-16 · S2 — prova de SEMÂNTICA DE TRANSAÇÃO do canal (sem escrita)
(`S2 CONTROLLED EXECUTION READINESS-01`, 2026-11-13)
Status.....: PREPARADO, NÃO EXECUTADO.
Pergunta...: Uma chamada única do canal (MCP execute_sql) com várias
             instruções entre BEGIN e o fim é executada como UMA transação,
             numa só sessão? É o que a 5362 exige (begin; … commit;) e o que
             o SQL Editor não garantiu na S1 (42P01 de _v116_s1_before).
Como.......: a instrução 2 grava um parâmetro LOCAL DA TRANSAÇÃO
             (set_config(..., true) — não é dado, não persiste na sessão);
             as instruções 3 e 4 o leem; a última levanta o relatório por
             RAISE (ERRCODE 55000), o que aborta a transação. Nenhuma
             tabela é lida ou escrita; nenhum COMMIT existe no arquivo.
Esperado...: ERRO 55000 com
               TXPROBE mesma_transacao=SIM ... xid_atribuido=nao
             · mesma_transacao=SIM  → as instruções compartilham a transação
             · xid_atribuido=nao    → nada foi escrito (nenhum xid alocado)
STOP.......: mesma_transacao=NAO (o canal não serve para a 5362), qualquer
             outro erro, ou retorno sem erro.
================================================================
*/
begin;
select set_config('mmkyu.v116_tx_probe', 'SIM', true) as marcou;
select pg_backend_pid() as pid_2;
select current_setting('mmkyu.v116_tx_probe', true) as leu_3;
do $txprobe$
begin
  raise exception using errcode = '55000', message = format(
    'TXPROBE mesma_transacao=%s · em_bloco_de_transacao=%s · xid_atribuido=%s · somente_leitura=%s',
    case when current_setting('mmkyu.v116_tx_probe', true) = 'SIM' then 'SIM' else 'NAO' end,
    case when now() = statement_timestamp() then 'indeterminado(instrucao_unica)' else 'SIM' end,
    case when txid_current_if_assigned() is null then 'nao' else 'SIM' end,
    current_setting('transaction_read_only'));
end;
$txprobe$;
rollback;
