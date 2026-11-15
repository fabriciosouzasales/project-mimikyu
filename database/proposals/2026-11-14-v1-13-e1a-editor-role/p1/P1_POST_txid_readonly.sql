/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: P1_POST_txid_readonly.sql — prova de que a transação do ensaio P1 foi DESFEITA
Versão......: 1.0 (2026-11-15, `V1-13 / E1-A | P1 INDEPENDENT ARTIFACT AUDIT-04`)
Status......: PROPOSTA — NÃO EXECUTADA. Leitura do LIVE NÃO autorizada nesta rodada.
Uso.........: logo depois do ensaio, com o "txid" do JSON da sentinela:
                psql -X -v ON_ERROR_STOP=1 -v txid=<número> -f P1_POST_txid_readonly.sql
              Esperado: estado_transacao = 'aborted'. 'committed' = INCIDENTE
              (parar tudo e acionar a reversão R5370 → R5366); 'in progress' =
              sessão do ensaio ainda aberta (encerrar e repetir esta leitura);
              NULL = txid fora da retenção do clog (repetir mais cedo) ou inválido.
              Sem txid (falha antes de a transação gravar algo) → não se aplica:
              nada foi escrito, conferir só o pós-estado.
Forma.......: UMA instrução SELECT, sem escrita.
================================================================
*/
select pg_catalog.txid_status(:'txid'::bigint) as estado_transacao;
