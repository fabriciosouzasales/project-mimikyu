# 2830H — verificação estática local dos envelopes (não conecta a banco). Uso: python3 tools/static_check.py
import re,sys,pathlib
H=pathlib.Path(__file__).resolve().parent.parent
def code(s):  # remove -- comments, keep strings
    out=[]
    for l in s.splitlines():
        i=l.find('--')
        out.append(l if i<0 else l[:i])
    return '\n'.join(out)
def nostr(c):
    c=re.sub(r"\$re\$.*?\$re\$","''",c,flags=re.S)
    return re.sub(r"'(?:[^']|'')*'","''",c)
res=[]
def chk(name,cond,detail=''):
    res.append((name,bool(cond),detail))
for f,exp,tag in [('2830H_E01_section1_structural.sql',['1.1','1.2','1.3','1.4','1.5','1.6','1.7','1.8','1.9','1.10','1.11','1.12'],'h2830_e01'),
                  ('2830H_E02_identity_terminal_D1_D5.sql',['D1','D2','D3','D4','D5'],'h2830_e02')]:
    s=(H/f).read_text(encoding='utf-8'); c=code(s); U=c.upper()
    chk(f+': 1 DO por arquivo', len(re.findall(r'\bDO\s+\$',c))==1)
    chk(f+': dollar-quote abre/fecha', c.count('$'+tag+'$')==2 and c.rstrip().endswith('$'+tag+'$;'))
    body=c.split('$'+tag+'$')[1]
    bodyns=nostr(body)
    stmts_outside=c.split('$'+tag+'$')[0].strip()
    chk(f+': nada executável fora do DO', stmts_outside.upper().strip()=='DO')
    for tok in [r'\bCOMMIT\b',r'\bROLLBACK\b',r'\bCREATE\b',r'\bALTER\b',r'\bDROP\b',r'\bTEMP\b',r'\bTEMPORARY\b',r'SET_CONFIG',r'\bSET\s+ROLE\b',r'\bSET\s+LOCAL\b',r'\bSET\s+SESSION\b',r'\bGRANT\b',r'\bREVOKE\b',r'\bTRUNCATE\b',r'\bDELETE\b',r'\bUPDATE\b',r'PG_SLEEP',r'DBLINK',r'\bNET\.',r'\bPERFORM\b',r'\bEXECUTE\b',r'RAISE\s+NOTICE',r'RAISE\s+WARNING',r'RAISE\s+INFO',
                r'\bCOMMENT\b',r'\bSECURITY\s+LABEL\b',r'\bREINDEX\b',r'\bREFRESH\b',r'\bIMPORT\b',r'\bLISTEN\b',r'\bNOTIFY\b',
                r'\bLOAD\b',r'\bCALL\b',r'\bCOPY\b',r'\bLOCK\b',r'\bMERGE\b']:
        chk(f+f': proibido ausente {tok}', not re.search(tok,bodyns.upper()))
    cases=re.findall(r"v_case\s*:=\s*'([^']+)'",body)
    chk(f+': casos na ordem = esperado', cases==exp, str(cases))
    exp_arr=re.search(r"c_expected\s+CONSTANT\s+text\[\]\s*:=\s*ARRAY\[(.*?)\]",body,re.S).group(1)
    chk(f+': c_expected = esperado', re.findall(r"'([^']+)'",exp_arr)==exp)
    codes=set(re.findall(r"ERRCODE\s*=\s*'([A-Z0-9]{5})'",body))
    chk(f+': ERRCODEs só H283C/F/P', codes<= {'H283C','H283F','H283P'}, str(codes))
    chk(f+': H283P exatamente 1', len(re.findall(r"ERRCODE\s*=\s*'H283P'",body))==1)
    # H283P é o último RAISE do corpo
    last=[m.group(0) for m in re.finditer(r"ERRCODE\s*=\s*'H283[CFP]'",body)][-1]
    chk(f+': último sinal é H283P', "H283P" in last)
    # cada caso: 1 sinal H283C, 1 handler H283C, 1 handler H283F re-raise, 1 WHEN OTHERS convertendo
    blocks=re.split(r"v_case\s*:=\s*'[^']+'\s*;",body)[1:]
    for cid,b in zip(cases,blocks):
        b=b.split('v_case :=')[0]
        ok = (len(re.findall(r"ERRCODE\s*=\s*'H283C'",b))==1 and
              "WHEN SQLSTATE 'H283C'" in b and "WHEN SQLSTATE 'H283F' THEN RAISE;" in b and
              'v_done := v_done || v_case' in b)
        chk(f+f': caso {cid} estrutura de subtransação', ok)
        # negativos: todo "EXCEPTION WHEN OTHERS THEN v_got := true" deve ser seguido de checagem de sqlstate+constraint
        negs=len(re.findall(r'EXCEPTION WHEN OTHERS THEN\s+v_got := true;',b))
        sqlst=len(re.findall(r"v_state <> '(23514|23505)' OR v_con IS DISTINCT FROM '",b))
        if negs: chk(f+f': caso {cid} negativos={negs} com SQLSTATE+constraint', sqlst>=1 and 'IF NOT v_got' in b, f'negs={negs} checks={sqlst}')
    # BEGIN/END balance (END IF/LOOP excluídos)
    nb=len(re.findall(r'\bBEGIN\b',U)); ne=len(re.findall(r'\bEND\b(?!\s+(IF|LOOP))',U))
    chk(f+': BEGIN/END balanceados', nb==ne, f'{nb}/{ne}')
    n_if=len(re.findall(r'(?<!END )\bIF\b',U)); n_eif=len(re.findall(r'\bEND\s+IF\b',U))
    chk(f+': IF/END IF balanceados', n_if==n_eif, str(n_if)+'/'+str(n_eif))
    chk(f+': parênteses balanceados', nostr(c).count('(')==nostr(c).count(')'))
    chk(f+': aspas simples pares', c.count("'")%2==0)
    ins=re.findall(r'INSERT INTO [^;]*;',body,re.S)
    chk(f+f': INSERTs={len(ins)} todos com marcador', all('v_marker' in i for i in ins))
for f in ['2830H_E00_precheck_inventory.sql','2830H_E99_postcheck_residue.sql']:
    raw=re.sub(r"\$re\$.*?\$re\$","''",(H/f).read_text(encoding='utf-8'),flags=re.S)
    c=code(raw); U=nostr(c).upper()
    chk(f+': 1 statement', U.count(';')==1 and U.rstrip().endswith(';'))
    for tok in [r'\bINSERT\b',r'\bUPDATE\b',r'\bDELETE\b',r'\bCREATE\b',r'\bALTER\b',r'\bDROP\b',r'SET_CONFIG',r'\bSET\b',r'\bDO\b',r'\bTEMP\b',
                r'\bINTO\b',r'\bGRANT\b',r'\bREVOKE\b',r'\bCOMMENT\b',r'\bSECURITY\s+LABEL\b',r'\bREINDEX\b',r'\bREFRESH\b',r'\bIMPORT\b',
                r'\bTRUNCATE\b',r'\bMERGE\b',r'\bCOPY\b',r'\bCALL\b',r'\bLOCK\b',r'\bLISTEN\b',r'\bNOTIFY\b']:
        chk(f+f': ausente {tok}', not re.search(tok,U))
    chk(f+': parênteses balanceados', nostr(c).count('(')==nostr(c).count(')'))

# ---------------------------------------------------------------------------
# CORRECTION-01: 1.12 com MAINTAIN; baselines E00/E99; P7
# ---------------------------------------------------------------------------
import json
PRIVS=['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']
e01=(H/'2830H_E01_section1_structural.sql').read_text(encoding='utf-8')
b112=code(e01).split("v_case := '1.12'")[1]
arrs=re.findall(r"unnest\(ARRAY\[([^\]]*)\]\)\s+AS\s+p\(priv\)",b112)
chk('1.12: 2 matrizes de privilégio', len(arrs)==2, str(len(arrs)))
chk('1.12: cada matriz = 8 privilégios PG17 (inclui MAINTAIN)', all(re.findall(r"'([A-Z]+)'",a)==PRIVS for a in arrs))
chk('1.12: anon e authenticated conferidos', "has_table_privilege('anon'" in b112 and "has_table_privilege('authenticated'" in b112)
e00=(H/'2830H_E00_precheck_inventory.sql').read_text(encoding='utf-8')
e99=(H/'2830H_E99_postcheck_residue.sql').read_text(encoding='utf-8')
def block(t,name):
    m=re.search(r'-- '+name+r':BEGIN\n(.*?)\n\s*-- '+name+r':END',t,re.S); return m.group(1) if m else None
for name in ['BASELINE-BUILDER','FREEZE-CANON']:
    a,b=block(e00,name),block(e99,name)
    chk(f'{name}: presente em E00 e E99', a is not None and b is not None)
    chk(f'{name}: idêntico byte a byte E00 x E99', a is not None and a==b)
canon_txt=re.search(r"SELECT '(\{.*?\})'::jsonb AS c",block(e00,'FREEZE-CANON') or '',re.S)
canon=json.loads(canon_txt.group(1)) if canon_txt else {}
chk('CANON: JSON válido', bool(canon))
req={'trait','profile','profile_trait','mapping','mapping_null_signature','card_variant','card_variant_ec_nonnull','staging_rows','staging_max_upd_utc','staging_status','operational_tristate','cancelled_without_key','lineage','jobs','jobs_by_status','jobs_max_upd_utc','jobs_in_flight'}
chk('CANON: chaves canônicas exatas', set(canon)==req, str(sorted(set(canon)^req)))
chk('CANON: staging_status soma = staging_rows', sum(canon.get('staging_status',{}).values())==canon.get('staging_rows'))
chk('CANON: jobs_by_status soma = jobs', sum(canon.get('jobs_by_status',{}).values())==canon.get('jobs'))
chk('CANON: sem chaves sem valor canônico (action_log, mapping_trait, marker_*)', not ({'action_log','mapping_trait','marker_trait','marker_profile','marker_mapping'} & set(canon)))
bkeys=set(re.findall(r"^\s*'([a-z_]+)',\s*",block(e00,'BASELINE-BUILDER') or '',re.M))
chk('BUILDER: toda chave canônica é produzida pelo builder', req<=bkeys, str(sorted(req-bkeys)))
g00=['g_objects_1x','g_objects_D','g_roles_1_12','g_pg17_maintain_privilege','g_game_source','g_freeze_canonical_equal','g_no_sequences_touched_now',
     'g_p7_all_classified','g_p7_identity_pinned','g_p7_search_path_safe','g_p7_no_external_or_dynamic','g_p7_no_ddl','g_p7_lexically_supported',
     'g_p7_no_unresolved','g_p7_no_unqualified_dml','g_p7_writes_in_scope','g_p7_closure_complete','g_no_rules',
     'g_evt_inventory_complete','g_evt_ddl_only','g_evt_all_adjudicated','g_rls_bypass','g_no_residue','g_no_concurrency']   # G-1: os 24 gates, todos com definição conferida
c00=code(e00)
for gname in g00: chk(f'E00: gate {gname} definido', re.search(r'AS\s+'+gname+r'\b',c00) is not None)
_gcte=c00[c00.index('\ngates AS ('):c00.index('\nSELECT to_jsonb(g)')]
_gdef=re.findall(r'AS\s+(g_[A-Za-z0-9_]+)',_gcte)
chk('E00: CTE gates define EXATAMENTE os 24 gates reconciliados (sem extra, sem falta, sem duplicata)', sorted(_gdef)==sorted(g00) and len(_gdef)==len(set(_gdef))==24, str(sorted(set(_gdef)^set(g00))))
# Predicado de cada gate (CORRECTION-01): o nome definido não basta — o segmento que precede 'AS <gate>' precisa conter
# os termos que o tornam efetivo, e nenhum gate pode ser esvaziado por 'WHERE false' / 'OR true' / 'true AS'.
_parts=re.split(r'AS\s+(g_[A-Za-z0-9_]+)',_gcte)
_seg={_parts[i]:_parts[i-1] for i in range(1,len(_parts),2)}
GATE_TERMS={
 'g_objects_1x':["'constraints_1x'","= 7","'indexes_1x'","= 4"], 'g_objects_D':["'indexes_D'","= 5"],
 'g_roles_1_12':["'roles_anon_authenticated'","= 2"], 'g_pg17_maintain_privilege':[">= 170000"],
 'g_game_source':["'game_pokemon'","'source_tcgdex'","= 1"], 'g_freeze_canonical_equal':["NOT EXISTS (SELECT 1 FROM canon_diff)"],
 'g_no_sequences_touched_now':["FROM seq s","r.touched_now"],
 'g_p7_all_classified':["gate_scope","class IN ('UNCLASSIFIED','DENIED')"], 'g_p7_identity_pinned':["gate_scope","class = 'ALLOWLIST_MISMATCH'"],
 'g_p7_search_path_safe':["gate_scope","search_path_unsafe"], 'g_p7_no_external_or_dynamic':["gate_scope","external_signal OR dynamic_sql"],
 'g_p7_no_ddl':["gate_scope","ddl_statement"], 'g_p7_lexically_supported':["gate_scope","unsupported_lexeme"],
 'g_p7_no_unresolved':["p7_unresolved_qualified WHERE gate_scope","resolution IN ('UNRESOLVED','DENIED')"],
 'g_p7_no_unqualified_dml':["p7_unqualified_writes WHERE gate_scope"], 'g_p7_writes_in_scope':["w.gate_scope","NOT w.target_exists","w.target NOT IN"],
 'g_p7_closure_complete':["p7_reach WHERE gate_scope AND depth >= 8"], 'g_no_rules':["FROM p7_rules","rel.gate_scope"],
 'g_evt_inventory_complete':["pg_catalog.pg_event_trigger","FROM evt)"], 'g_evt_ddl_only':["FROM evt WHERE enabled <> 'D'"],
 'g_evt_all_adjudicated':["FROM evt_unadjudicated"], 'g_rls_bypass':["force_rls","o.owner <> current_user"],
 'g_no_residue':["'marker_trait'","'marker_profile'","'marker_mapping'"], 'g_no_concurrency':["'other_sessions_in_txn'","= 0"]}
chk('E00: termos de predicado declarados para os 24 gates', set(GATE_TERMS)==set(g00))
for _g,_terms in GATE_TERMS.items():
    _t=_seg.get(_g,'')
    chk(f'E00: predicado de {_g} contém {len(_terms)} termo(s) efetivo(s) e não é esvaziado',
        all(x in _t for x in _terms) and not re.search(r'WHERE\s+false|OR\s+true|^\s*,?\s*true\s*$',_t,re.I|re.M), _g)
chk('E00: gate antigo g_no_enabled_event_triggers substituído (não coexistem)', re.search(r'AS\s+g_no_enabled_event_triggers\b',c00) is None)
chk('E00: gate_pass agrega TODOS os g_* (bool_and + NULL=falha)', 'bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g))' in c00 and 'WHERE v IS NULL' in c00)
chk('E00: exporta d_baseline e d_baseline_md5', "'d_baseline'," in c00 and "'d_baseline_md5'," in c00 and 'md5(b::text)' in c00)
chk('E00: P7 fecho recursivo + classificação + UNCLASSIFIED', 'WITH RECURSIVE walk' in c00 and "'UNCLASSIFIED'" in e00 and 'p7_allowlist' in c00)
chk('E00: P7 raízes trigger+check+default+index', all(x in e00 for x in ["'trigger '","'check '","'default '","'index '"]))
c99=code(e99)
for ph in ['__E00_D_BASELINE__','__E00_D_BASELINE_MD5__','__E00_ROLE_SETTING_ROWS__']:
    chk(f'E99: marcador {ph} exatamente 1x no código', len(re.findall(r"'"+ph+r"'",c99))==1)
g99=['g_captured_present','g_captured_integrity','g_keys_identical','g_baseline_equal','g_freeze_canonical_equal','g_marker_absent','g_no_open_txn_others','g_lock_timeout_default','g_role_setting_unchanged']
for gname in g99: chk(f'E99: gate {gname} definido', re.search(r'AS\s+'+gname+r'\b',c99) is not None)
chk('E99: gate_pass agrega TODOS os g_* (bool_and + NULL=falha)', 'bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g))' in c99 and 'WHERE v IS NULL' in c99)
chk('E99: diff por chave sobre a UNIÃO das chaves', 'all_keys' in c99 and 'UNION' in c99 and 'd_diff' in c99)


# ---------------------------------------------------------------------------
# CORRECTION-02: MODELO DO P7 v3 (sem banco). Os padrões, palavras-chave,
# lista negra e pinos da allowlist são EXTRAÍDOS do próprio E00 — o modelo
# testa o mesmo texto que o PostgreSQL executará. Tradução ARE→Python:
# \m e \M → \b (fronteiras de palavra); o resto é sintaxe comum.
# ---------------------------------------------------------------------------
import hashlib
e00=(H/'2830H_E00_precheck_inventory.sql').read_text(encoding='utf-8')
REP=dict((n,v) for v,n in re.findall(r"\$re\$(.*?)\$re\$\s+AS\s+([a-z_]+)",e00,re.S))
chk('P7 modelo: 12 padrões extraídos do E00', set(REP)=={'lex','unsupported_raw','unsupported_lexed','lock_or_upsert','qcall','ucall','qdml','udml','signal_raw','dynamic_lexed','ddl_lexed','sql_into_lexed'}, str(sorted(REP)))
def are(p): return p.replace(r'\m',r'\b').replace(r'\M',r'\b')
R={k:re.compile(are(v),re.I if k in ('lock_or_upsert','qdml','udml','signal_raw','dynamic_lexed','ddl_lexed','sql_into_lexed') else 0) for k,v in REP.items()}
def lf(src): return src.replace('\r\n','\n')   # D-6: normalização determinística, SÓ CRLF (CR isolado permanece)
KW=set(re.findall(r"'([a-z_]+)'",re.search(r"p7_keywords\(word\) AS \(\s*SELECT unnest\(ARRAY\[(.*?)\]\)",e00,re.S).group(1)))
DENY=set(re.findall(r"\('([a-z_]+)'\)",re.search(r"p7_denylist\(proname\) AS \(\s*VALUES(.*?)\n\),",e00,re.S).group(1)))
ALLOW={}
for row in re.findall(r"^\s*\(('(?:internal|public|extensions)'.*?)\),?\s*$",re.search(r"p7_allowlist\(.*?\) AS \(\s*VALUES(.*?)\n\),",e00,re.S).group(1),re.M):
    f=[x.strip() for x in re.findall(r"ARRAY\['[^']*'\]|NULL::text\[\]|'(?:[^']|'')*'|true|false|NULL",row)]
    unq=lambda x: None if x in ('NULL','NULL::text[]') else (x=='true' if x in ('true','false') else (re.findall(r"'([^']*)'",x) if x.startswith('ARRAY') else x[1:-1].replace("''","'")))
    v=[unq(x) for x in f]
    ALLOW[(v[0],v[1],v[2])]=dict(lang=v[3],secdef=v[4],vol=v[5],config=v[6],md5=v[7],csym=v[8],ext=v[9],cls=v[10])
chk('P7 modelo: allowlist com 12 entradas pinadas', len(ALLOW)==12, str(len(ALLOW)))
# catálogo simulado (pg_catalog) — suficiente para os corpos reais e os controles
PGCAT_FN={'upper','lower','btrim','trim','regexp_replace','cardinality','now','coalesce','format','count','array_agg',
          'jsonb_typeof','jsonb_exists','gen_random_uuid','unnest','md5','pg_notify','set_config','pg_sleep','txid_current'}
PGCAT_TYPE={'text','uuid','int4','varchar','numeric','timestamp','bool'}
SCOPE={'public.card_edition_context_trait','public.card_edition_context_profile','public.card_edition_context_profile_trait',
       'public.card_edition_context_external_mapping','public.card_edition_context_external_mapping_trait'}
RELATIONS=SCOPE|{'public.card_variant','public.catalog_admin_action_log','public.catalog_variant_import_row'}
def p7_gate(fns, ext_members):
    """fns: dict fqkey->(nsp,name,idargs,lang,secdef,vol,config,prosrc). Retorna (pass, motivos)."""
    reasons=[]; procs={(f[0],f[1]) for f in fns.values()}|{('pg_catalog',n) for n in PGCAT_FN}
    for k,(nsp,name,ida,lang,secdef,vol,cfg,src) in fns.items():
        # classificação
        if nsp=='pg_catalog':
            cls='DENIED' if name in DENY else 'BUILTIN'
        else:
            a=ALLOW.get((nsp,name,ida))
            if a is None: cls='UNCLASSIFIED'
            elif (lang!=a['lang'] or secdef!=a['secdef'] or (a['vol'] is not None and vol!=a['vol'])
                  or (a['config'] is not None and cfg!=a['config'])
                  or (a['md5'] is not None and hashlib.md5(lf(src).encode()).hexdigest()!=a['md5'])
                  or (a['csym'] is not None and src!=a['csym'])
                  or (a['ext'] is not None and k not in ext_members.get(a['ext'],set()))): cls='ALLOWLIST_MISMATCH'
            else: cls=a['cls']
        if cls in ('UNCLASSIFIED','DENIED'): reasons.append('g_p7_all_classified:'+k)
        if cls=='ALLOWLIST_MISMATCH': reasons.append('g_p7_identity_pinned:'+k)
        if lang in ('c','internal'): continue
        lexed=R['lex'].sub(' ',src)
        if nsp!='pg_catalog' and not (cfg is not None and sum(1 for c in cfg if c.startswith('search_path='))==1 and 'search_path=""' in cfg):
            reasons.append('g_p7_search_path_safe:'+k)
        if R['signal_raw'].search(src) or (lang=='plpgsql' and R['dynamic_lexed'].search(lexed)): reasons.append('g_p7_no_external_or_dynamic:'+k)
        if R['unsupported_raw'].search(src) or R['unsupported_lexed'].search(lexed): reasons.append('g_p7_lexically_supported:'+k)
        if R['ddl_lexed'].search(lexed) or (lang=='sql' and R['sql_into_lexed'].search(lexed)): reasons.append('g_p7_no_ddl:'+k)
        t=R['lock_or_upsert'].sub(' ',lexed)
        for m in R['qcall'].finditer(t):
            ref=(m.group(1).lower(),m.group(2).lower())
            if ref not in procs and '.'.join(ref) not in RELATIONS: reasons.append('g_p7_no_unresolved:'+k+'->'+'.'.join(ref))
        for m in R['ucall'].finditer(t):
            n=m.group(1).lower()
            if n in KW: continue
            if n in DENY or not (n in PGCAT_FN or n in PGCAT_TYPE): reasons.append('g_p7_no_unresolved:'+k+'->'+n)
        for m in R['qdml'].finditer(t):
            tgt=m.group(4).lower()+'.'+m.group(5).lower()
            if tgt not in RELATIONS or tgt not in SCOPE: reasons.append('g_p7_writes_in_scope:'+k+'->'+tgt)
        for m in R['udml'].finditer(t): reasons.append('g_p7_no_unqualified_dml:'+k+'->'+m.group(4))
    return (not reasons, reasons)
# corpos REAIS do repositório (mesma extração dos pinos)
REPO=H.parent.parent.parent
real={}
for f,nsp_default in [('proposals/2026-09-18-edition-context-axis/2206_create_edition_context_composition_guards.sql',None),
                      ('proposals/2026-09-18-edition-context-axis/2207_create_card_edition_context_external_mapping.sql',None),
                      ('schema/2095_create_normalize_external_catalog_value_function.sql',None)]:
    src=(REPO/f).read_text(encoding='utf-8')
    for m in re.finditer(r'CREATE OR REPLACE FUNCTION ([a-z_]+)\.([a-z_]+)\(([^)]*)\)(.*?)AS \$\$(.*?)\$\$;',src,re.S):
        nsp,name,args,hdr,body=m.groups()
        ida=' '.join(args.lower().split())
        lang=re.search(r'LANGUAGE (\w+)',hdr).group(1)
        vol='s' if 'STABLE' in hdr else ('i' if 'IMMUTABLE' in hdr else 'v')
        real[nsp+'.'+name]=(nsp,name,ida,lang,'SECURITY DEFINER' in hdr,vol,['search_path=""'],body)
real['extensions.unaccent(text)']=('extensions','unaccent','text','c',False,'s',None,'unaccent_dict')
real['extensions.unaccent(regdictionary, text)']=('extensions','unaccent','regdictionary, text','c',False,'s',None,'unaccent_dict')
EXT={'unaccent':{'extensions.unaccent(text)','extensions.unaccent(regdictionary, text)'}}
chk('P7 modelo: 12 funções reais carregadas', len(real)==12, str(len(real)))
ok,why=p7_gate(real,EXT)
chk('P7 CONTROLE POSITIVO: definições reais do repositório passam (sem falso STOP)', ok, '; '.join(why[:5]))
def body_with(extra): return '\nBEGIN\n'+extra+'\n    RETURN NEW;\nEND;\n'
EXPECT={
 'chamada NÃO qualificada a função desconhecida':'g_p7_no_unresolved',
 'chamada NÃO qualificada a builtin negado (pg_notify)':'g_p7_no_unresolved',
 'DML NÃO qualificado (UPDATE card_variant)':'g_p7_no_unqualified_dml',
 'DML NÃO qualificado (INSERT INTO audit_log)':'g_p7_no_unqualified_dml',
 'DML NÃO qualificado com ONLY (DELETE FROM ONLY t)':'g_p7_no_unqualified_dml',
 'DML qualificado FORA do escopo (public.card_variant)':'g_p7_writes_in_scope',
 'DML qualificado para relação inexistente (public.ghost)':'g_p7_writes_in_scope',
 'chamada qualificada NÃO resolvida (internal.ghost_fn)':'g_p7_no_unresolved',
 'função permitida pelo NOME com corpo alterado (md5)':'g_p7_identity_pinned',
 'função permitida pelo NOME com assinatura diferente':'g_p7_all_classified',
 'função permitida com SECURITY DEFINER divergente':'g_p7_identity_pinned',
 'função permitida com linguagem divergente':'g_p7_identity_pinned',
 'função C permitida com símbolo divergente':'g_p7_identity_pinned',
 'search_path ausente':'g_p7_search_path_safe',
 'search_path inseguro (public)':'g_p7_search_path_safe',
 'search_path duplicado':'g_p7_search_path_safe',
 'search_path com pg_temp':'g_p7_search_path_safe',
 'função não classificada alcançada':'g_p7_all_classified',
 'SQL dinâmico (EXECUTE)':'g_p7_no_external_or_dynamic',
 'E-string escondendo conteúdo':'g_p7_lexically_supported',
 'dollar-quote interno':'g_p7_lexically_supported',
 'identificador entre aspas duplas chamado':'g_p7_lexically_supported',
 'nome em três partes':'g_p7_lexically_supported',
 'espaço entre schema, ponto e função (x . f)':'g_p7_no_unresolved',
 'chamada aninhada não qualificada (f(g(x)))':'g_p7_no_unresolved',
 'sinal de efeito externo (net.http_post)':'g_p7_no_external_or_dynamic',
 'DDL estático no corpo (CREATE TEMP TABLE)':'g_p7_no_ddl',
 'DDL estático no corpo (GRANT)':'g_p7_no_ddl',
 'DDL estático no corpo (COMMENT ON)':'g_p7_no_ddl',
 'função sql com SELECT INTO (cria tabela)':'g_p7_no_ddl',
 'EOL: CR isolado (não é CRLF) no corpo pinado':'g_p7_identity_pinned',
 'EOL: CRLF + alteração de conteúdo':'g_p7_identity_pinned',
 'EOL: CRLF + SECURITY DEFINER divergente':'g_p7_identity_pinned'}
def neg(label, fns):
    ok,why=p7_gate(fns,EXT); exp=EXPECT[label]
    chk('P7 CONTROLE NEGATIVO bloqueado: '+label+' [gate '+exp+']', (not ok) and any(w.startswith(exp+':') for w in why), 'motivos='+str(why[:3]))
    return why
base=dict(real)
def mut_body(fq, newbody):
    d=dict(base); t=list(d[fq]); t[7]=newbody; d[fq]=tuple(t); return d
evil=('internal','evil_fn','', 'plpgsql', True,'v',['search_path=""'], body_with('    PERFORM 1;'))
neg('chamada NÃO qualificada a função desconhecida', {**base,'x':('internal','x_trigger','','plpgsql',True,'v',['search_path=""'],body_with('    NEW.a := evil_fn(1);'))})
neg('chamada NÃO qualificada a builtin negado (pg_notify)', mut_body('internal.guard_edition_context_trait_active', body_with("    PERFORM pg_notify('c', 'x');")))
neg('DML NÃO qualificado (UPDATE card_variant)', mut_body('internal.guard_edition_context_trait_active', body_with('    UPDATE card_variant SET is_default = false;')))
neg('DML NÃO qualificado (INSERT INTO audit_log)', mut_body('internal.guard_edition_context_trait_active', body_with('    INSERT INTO audit_log (a) VALUES (1);')))
neg('DML NÃO qualificado com ONLY (DELETE FROM ONLY t)', mut_body('internal.guard_edition_context_trait_active', body_with('    DELETE FROM ONLY t WHERE true;')))
neg('DML qualificado FORA do escopo (public.card_variant)', mut_body('internal.guard_edition_context_trait_active', body_with('    UPDATE public.card_variant SET is_default = false;')))
neg('DML qualificado para relação inexistente (public.ghost)', mut_body('internal.guard_edition_context_trait_active', body_with('    DELETE FROM public.ghost;')))
neg('chamada qualificada NÃO resolvida (internal.ghost_fn)', mut_body('internal.guard_edition_context_trait_active', body_with('    PERFORM internal.ghost_fn(1);')))
neg('função permitida pelo NOME com corpo alterado (md5)', mut_body('internal.guard_edition_context_trait_active', real['internal.guard_edition_context_trait_active'][7].replace('RETURN NEW;','RETURN NULL;')))
d=dict(base); t=list(d['public.normalize_external_catalog_value']); t[2]='p_value text, p_extra text'; d['public.normalize_external_catalog_value']=tuple(t)
neg('função permitida pelo NOME com assinatura diferente', d)
d=dict(base); t=list(d['internal.seal_edition_context_composition']); t[4]=False; d['internal.seal_edition_context_composition']=tuple(t)
neg('função permitida com SECURITY DEFINER divergente', d)
d=dict(base); t=list(d['public.normalize_external_catalog_value']); t[3]='plpgsql'; d['public.normalize_external_catalog_value']=tuple(t)
neg('função permitida com linguagem divergente', d)
d=dict(base); t=list(d['extensions.unaccent(text)']); t[7]='evil_symbol'; d['extensions.unaccent(text)']=tuple(t)
neg('função C permitida com símbolo divergente', d)
neg('função C permitida fora da extensão', {k:v for k,v in base.items()} ) if False else None
ok_ext,_=p7_gate(base,{'unaccent':set()}); chk('P7 CONTROLE NEGATIVO bloqueado: função C permitida sem pertença à extensão', not ok_ext)
for label,cfg in [('search_path ausente',None),('search_path inseguro (public)',['search_path=public']),
                  ('search_path duplicado',['search_path=""','search_path=public']),('search_path com pg_temp',['search_path=pg_temp'])]:
    d=dict(base); t=list(d['internal.guard_edition_context_trait_active']); t[6]=cfg; d['internal.guard_edition_context_trait_active']=tuple(t)
    neg(label, d)
neg('função não classificada alcançada', {**base,'internal.evil_fn':evil})
neg('SQL dinâmico (EXECUTE)', mut_body('internal.guard_edition_context_trait_active', body_with("    EXECUTE 'SELECT 1';")))
neg('E-string escondendo conteúdo', mut_body('internal.guard_edition_context_trait_active', body_with("    NEW.a := E'x\\\\' ; evil_fn(1) ; ''';")))
neg('dollar-quote interno', mut_body('internal.guard_edition_context_trait_active', body_with("    NEW.a := $q$ x $q$;")))
neg('identificador entre aspas duplas chamado', mut_body('internal.guard_edition_context_trait_active', body_with('    PERFORM "evil"(1);')))
neg('nome em três partes', mut_body('internal.guard_edition_context_trait_active', body_with('    PERFORM db.internal.evil_fn(1);')))
neg('espaço entre schema, ponto e função (x . f)', mut_body('internal.guard_edition_context_trait_active', body_with('    PERFORM internal . evil_fn(1);')))
neg('chamada aninhada não qualificada (f(g(x)))', mut_body('internal.guard_edition_context_trait_active', body_with('    NEW.a := upper(evil_fn(1));')))
neg('sinal de efeito externo (net.http_post)', mut_body('internal.guard_edition_context_trait_active', body_with("    PERFORM net.http_post('u');")))
# controles positivos de NÃO-falso-STOP: comentário/literal/lock não são dependências
fine=body_with("    -- UPDATE que não é DML: evil_fn( update card_variant\n    /* INSERT INTO ghost (x) */\n    NEW.a := 'texto com evil_fn(1) e UPDATE card_variant';\n    PERFORM 1 FROM public.card_edition_context_trait t WHERE t.id = NEW.trait_id FOR UPDATE;")
d=mut_body('internal.guard_edition_context_trait_active', fine);
# ajusta o pino md5 do corpo modificado só neste controle positivo
key=('internal','guard_edition_context_trait_active',''); saved=dict(ALLOW[key]); ALLOW[key]['md5']=hashlib.md5(fine.encode()).hexdigest()
ok,why=p7_gate(d,EXT); ALLOW[key]=saved
chk('P7 CONTROLE POSITIVO: comentário, literal e FOR UPDATE não geram dependência', ok, '; '.join(why))


# ---------------------------------------------------------------------------
# STOP-ADJUDICATION-01 (proposta): D-6 (EOL), P7 sem DDL, P7-EVT (event
# triggers). Sem banco. Os valores LIVE usados abaixo vêm da Tentativa 03
# (LIVE-STAGE1-EXECUTION-RECORD.md §6) e são citados como evidência, não
# consultados.
# ---------------------------------------------------------------------------
# D-6.1 — pinos = md5 do corpo do repositório normalizado (os dois lados)
for (nsp,name,ida),a in ALLOW.items():
    if a['md5'] is None: continue
    fq=nsp+'.'+name
    chk(f'D-6: pino de {fq} = md5(LF(corpo do repositório))', fq in real and hashlib.md5(lf(real[fq][7]).encode()).hexdigest()==a['md5'])
    chk(f'D-6: corpo do repositório de {fq} sem CR', fq in real and '\r' not in real[fq][7])
chk('D-6: E00 compara md5(replace(prosrc, CRLF, LF)) com o pino', "md5(replace(f.prosrc, chr(13) || chr(10), chr(10))) IS DISTINCT FROM a.body_md5" in c00)
chk('D-6: E00 não compara mais md5(prosrc) bruto com o pino', 'md5(f.prosrc) IS DISTINCT FROM a.body_md5' not in c00)
chk('D-6: E00 exporta md5 bruto + LF + cr_count + crlf_count + d_p7_eol_normalized',
    all(x in c00 for x in ["'body_md5', CASE","'body_md5_lf', CASE","'cr_count',","'crlf_count',","'d_p7_eol_normalized',"]))
# D-6.2 — reprodução da evidência LIVE (Tentativa 03): o corpo do repositório com LF→CRLF
nec='public.normalize_external_catalog_value'
live_nec=real[nec][7].replace('\n','\r\n')
chk('D-6 EVIDÊNCIA: repo LF→CRLF reproduz md5_raw LIVE 81361bb8… (L2)', hashlib.md5(live_nec.encode()).hexdigest()=='81361bb8f52ce142803d69c2b3028ae8')
chk('D-6 EVIDÊNCIA: len 104 e cr_count 2 iguais à L2', len(live_nec)==104 and live_nec.count('\r')==2)
chk('D-6 EVIDÊNCIA: md5 LF do corpo LIVE reconstruído = pino 1fdc2e7e…', hashlib.md5(lf(live_nec).encode()).hexdigest()=='1fdc2e7ebe2297f8db85be4aad2e5d33')
ok,why=p7_gate(mut_body(nec, live_nec),EXT)
chk('D-6 CONTROLE POSITIVO: corpo LIVE (CRLF) com demais atributos iguais passa o pino normalizado', ok, '; '.join(why[:3]))
neg('EOL: CR isolado (não é CRLF) no corpo pinado', mut_body(nec, real[nec][7].replace('\n','\r',1)))
neg('EOL: CRLF + alteração de conteúdo', mut_body(nec, live_nec.replace("' '","'_'")))
d=mut_body(nec, live_nec); t=list(d[nec]); t[4]=True; d[nec]=tuple(t)
neg('EOL: CRLF + SECURITY DEFINER divergente', d)
# P7 sem DDL — corpos reais sem DDL + controles negativos
for fq,v in real.items():
    if v[3] in ('c','internal'): continue
    lx=R['lex'].sub(' ',v[7])
    chk(f'P7-DDL: corpo real de {fq} sem comando DDL', not R['ddl_lexed'].search(lx) and not (v[3]=='sql' and R['sql_into_lexed'].search(lx)))
tg='internal.guard_edition_context_trait_active'
neg('DDL estático no corpo (CREATE TEMP TABLE)', mut_body(tg, body_with('    CREATE TEMP TABLE x (a int);')))
neg('DDL estático no corpo (GRANT)', mut_body(tg, body_with('    GRANT SELECT ON public.card_edition_context_trait TO anon;')))
neg('DDL estático no corpo (COMMENT ON)', mut_body(tg, body_with("    COMMENT ON TABLE public.card_edition_context_trait IS 'x';")))
neg('função sql com SELECT INTO (cria tabela)', mut_body(nec, "\n    SELECT 1 INTO public.ghost;\n"))
fine_ddl=body_with("    -- CREATE TABLE em comentário\n    NEW.a := 'DROP TABLE em literal';\n    NEW.created_at := now();")
key=('internal','guard_edition_context_trait_active',''); saved=dict(ALLOW[key]); ALLOW[key]['md5']=hashlib.md5(fine_ddl.encode()).hexdigest()
ok,why=p7_gate(mut_body(tg, fine_ddl),EXT); ALLOW[key]=saved
chk('P7-DDL CONTROLE POSITIVO: DDL em comentário/literal e identificador created_at não disparam', ok, '; '.join(why))

# P7-EVT — event triggers (CORRECTION-01: G-2 lógica de 3 valores, G-3 completude, G-4 identidade de 12 atributos)
DDL_EVENTS={'ddl_command_start','ddl_command_end','sql_drop','table_rewrite'}
EVT_EQ=['name','event','enabled','owner','fn','fn_language','fn_owner','fn_secdef','fn_md5_lf']   # '=' do SQL: NULL nunca casa
EVT_INDF=['tags','fn_config','fn_extension']                                                       # IS NOT DISTINCT FROM: NULL é estado pinado
EVT_ID=['name','event','tags','enabled','owner','fn','fn_language','fn_owner','fn_secdef','fn_config','fn_extension','fn_md5_lf']
m=re.search(r"evt_allowlist\((.*?)\) AS \(\s*(.*?)\n\),",e00,re.S)
chk('EVT: evt_allowlist presente no E00', m is not None)
EVT_COLS=[x.strip() for x in m.group(1).split(',')] if m else []
chk('EVT: evt_allowlist = 12 atributos de identidade + justification (G-4)', EVT_COLS==EVT_ID+['justification'], str(EVT_COLS))
allow_body=m.group(2) if m else ''
chk('EVT: tipos da allowlist vazia alinhados (boolean em fn_secdef, text[] em tags/fn_config)',
    re.findall(r"NULL::([a-z\[\]]+)",allow_body)==['text','text','text[]','text','text','text','text','text','boolean','text[]','text','text','text'])
def allow_rows(txt):
    """Extrai linhas VALUES (...) de um texto de allowlist; cada linha vira lista de literais."""
    rows=[]
    for r in re.findall(r"^\s*\(('(?:[^']|'')*'.*?)\),?\s*$",txt,re.M):
        f=re.findall(r"ARRAY\[[^\]]*\](?:::text\[\])?|'(?:[^']|'')*'|true|false|NULL(?:::[a-z\[\]]+)?",r)
        rows.append(f)
    return rows
def row_valid(f):
    """Regras para QUALQUER linha futura: 13 campos; justification não vazia; evento DDL; nenhum atributo de '=' em NULL."""
    if len(f)!=13: return False
    d=dict(zip(EVT_ID+['justification'],f))
    lit=lambda x: None if x.startswith('NULL') else x
    if lit(d['justification']) is None or not re.sub(r"^'|'$","",d['justification']).strip(): return False
    if lit(d['event']) is None or d['event'].strip("'") not in DDL_EVENTS: return False
    if any(lit(d[k]) is None for k in EVT_EQ): return False
    return True
ROWS=allow_rows(allow_body)
chk('EVT: evt_allowlist nasce VAZIA (nenhuma exceção; os 6 triggers NÃO inseridos)', 'WHERE false' in allow_body and len(ROWS)==0, str(len(ROWS)))
chk('EVT: toda linha presente na allowlist é válida (vácuo verdadeiro com 0 linhas)', all(row_valid(r) for r in ROWS))
GOOD="  ('pgrst_ddl_watch', 'ddl_command_end', NULL::text[], 'O', 'supabase_admin', 'extensions.pgrst_ddl_watch()', 'plpgsql', 'supabase_admin', true, NULL::text[], NULL, '"+'0'*32+"', 'L4 <prov>; justificativa (a)-(f)'),"
chk('EVT VALIDADOR controle positivo: linha sintética completa é aceita', row_valid(allow_rows(GOOD)[0]))
for label,bad in [('justificativa vazia',GOOD.replace("'L4 <prov>; justificativa (a)-(f)'","''")),
                  ('justificativa só com espaços',GOOD.replace("'L4 <prov>; justificativa (a)-(f)'","'   '")),
                  ('justificativa NULL',GOOD.replace("'L4 <prov>; justificativa (a)-(f)'","NULL")),
                  ('evento login',GOOD.replace("'ddl_command_end'","'login'")),
                  ('fn_md5_lf NULL',GOOD.replace("'"+'0'*32+"'","NULL")),
                  ('fn_secdef NULL',GOOD.replace(", true,",", NULL,")),
                  ('owner NULL',GOOD.replace("'O', 'supabase_admin'","'O', NULL")),
                  ('linha sem justification (12 campos)',GOOD.replace(", 'L4 <prov>; justificativa (a)-(f)'",""))]:
    chk('EVT VALIDADOR CONTROLE NEGATIVO rejeita linha futura: '+label, not row_valid(allow_rows(bad)[0]))
un=re.search(r"evt_unadjudicated AS \((.*?)\n\),",c00,re.S).group(1)
for col in EVT_EQ:
    chk(f"EVT: casamento a.{col} = e.{col} (NULL nunca casa)", re.search(r'\ba\.'+col+r'\s*=\s*e\.'+col+r'\b',un) is not None)
for col in EVT_INDF:
    chk(f"EVT: casamento a.{col} IS NOT DISTINCT FROM e.{col}", ('a.'+col+' IS NOT DISTINCT FROM e.'+col) in un)
chk("EVT: justificativa obrigatória também no SQL (NULLIF(btrim(a.justification), '') IS NOT NULL)", "NULLIF(btrim(a.justification), '') IS NOT NULL" in un)
chk("EVT: exceção só para evento DDL (lista literal no casamento)", "a.event IN ('ddl_command_start','ddl_command_end','sql_drop','table_rewrite')" in un)
chk("EVT: g_evt_ddl_only com a mesma lista DDL", "event NOT IN ('ddl_command_start','ddl_command_end','sql_drop','table_rewrite'))" in c00)
chk('EVT: inventário exporta identidade completa (tags, owner, fn, secdef, proconfig, extensão, md5 bruto e LF)',
    all(x in c00 for x in ['e.evttags','pg_get_userbyid(e.evtowner)','AS fn_secdef','AS fn_config','AS fn_extension','AS fn_md5_raw','AS fn_md5_lf']))
_evt=re.search(r"\nevt AS \((.*?)\n\),",c00,re.S).group(1)
chk('EVT G-3: CTE evt sem filtro — termina nos JOINs (nenhum WHERE fora da subconsulta de extensão)',
    _evt.rstrip().endswith('JOIN pg_language l  ON l.oid = p.prolang') and len(re.findall(r'\bWHERE\b',_evt))==1 and 'FROM pg_event_trigger e' in _evt)
chk('EVT G-3: g_evt_inventory_complete compara count(pg_event_trigger) DIRETO com count(evt)',
    re.search(r"\(SELECT count\(\*\) FROM pg_catalog\.pg_event_trigger\) = \(SELECT count\(\*\) FROM evt\)\s*AS g_evt_inventory_complete",c00) is not None)
chk("EVT: d_evt_catalog_count, d_evt_unadjudicated e d_evt_allowlist_absent exportados", all(x in c00 for x in ["'d_evt_catalog_count',","'d_evt_unadjudicated',","'d_evt_allowlist_absent',"]))
def eq3(a,b): return a is not None and b is not None and a==b      # SQL '='
def indf(a,b): return a==b                                          # IS NOT DISTINCT FROM
def evt_gate(live, allow, catalog_count=None):
    """Modelo com semântica SQL (G-2). catalog_count = count(pg_event_trigger) lido direto (G-3)."""
    reasons=[]
    if catalog_count is not None and catalog_count!=len(live): reasons.append('g_evt_inventory_complete:'+str(catalog_count)+'!='+str(len(live)))
    for e in live:
        if e['enabled']=='D': continue
        if e['event'] not in DDL_EVENTS: reasons.append('g_evt_ddl_only:'+e['name'])
        if not any(a['event'] in DDL_EVENTS and all(eq3(a[k],e[k]) for k in EVT_EQ) and all(indf(a[k],e[k]) for k in EVT_INDF)
                   and a.get('justification') is not None and a['justification'].strip()!='' for a in allow):
            reasons.append('g_evt_all_adjudicated:'+e['name'])
    return (not reasons, reasons)
def evt_join(catalog, procs):
    """Simula o CTE evt: JOIN interno de pg_event_trigger com pg_proc (trigger sem função some)."""
    return [dict(t, **procs[t['foid']]) for t in catalog if t['foid'] in procs]
# inventário da Tentativa 03 (nome, evento, estado = evidência LIVE; demais campos SINTÉTICOS só para o modelo)
T03=[('issue_graphql_placeholder','sql_drop'),('pgrst_ddl_watch','ddl_command_end'),('pgrst_drop_watch','sql_drop'),
     ('issue_pg_cron_access','ddl_command_end'),('issue_pg_net_access','ddl_command_end'),('issue_pg_graphql_access','ddl_command_end')]
live=[dict(name=n,event=ev,enabled='O',tags=None,owner='SYNTH_owner',fn='SYNTH.'+n+'()',fn_language='plpgsql',fn_owner='SYNTH_owner',
           fn_secdef=False,fn_config=None,fn_extension=None,fn_md5_lf='0'*32) for n,ev in T03]
ok,why=evt_gate(live,[],6)
chk('EVT REPRODUÇÃO: 6 habilitados + allowlist vazia ⇒ STOP (igual à Tentativa 03)', (not ok) and len([w for w in why if w.startswith('g_evt_all_adjudicated:')])==6)
allow=[dict(e,justification='L4 <prov>; justificativa (a)-(f)') for e in live]
ok,_=evt_gate(live,allow,6); chk('EVT CONTROLE POSITIVO: identidade completa adjudicada, NULL=NULL em tags/fn_config/fn_extension ⇒ passa', ok)
def evt_neg(label, live2, allow2, gate, cc=None):
    ok,why=evt_gate(live2,allow2,len(live2) if cc is None else cc)
    chk('EVT CONTROLE NEGATIVO bloqueado: '+label+' [gate '+gate+']', (not ok) and any(w.startswith(gate+':') for w in why), str(why[:2]))
def mut(i,**kw):
    l2=[dict(e) for e in live]; l2[i].update(kw); return l2
for fld,val in [('fn_md5_lf','f'*32),('fn','extensions.evil()'),('tags',['CREATE EXTENSION']),('owner','postgres'),('fn_owner','postgres'),
                ('fn_language','sql'),('enabled','A'),('event','ddl_command_start'),('name','renamed_hook')]:
    evt_neg(f'mesmo trigger, {fld} divergente', mut(1,**{fld:val}), allow, 'g_evt_all_adjudicated')
# G-4: alterações isoladas dos atributos novos
evt_neg('fn_secdef false→true (isolado)', mut(2,fn_secdef=True), allow, 'g_evt_all_adjudicated')
evt_neg('fn_config NULL→{search_path=""} (isolado)', mut(2,fn_config=['search_path=""']), allow, 'g_evt_all_adjudicated')
a2=[dict(a) for a in allow]; a2[2]['fn_config']=['search_path=""']
evt_neg('fn_config {search_path=""}→NULL (isolado)', live, a2, 'g_evt_all_adjudicated')
evt_neg('fn_config {search_path=""}→{search_path=public} (isolado)', mut(2,fn_config=['search_path=public']), a2, 'g_evt_all_adjudicated')
evt_neg('fn_extension NULL→pg_net (isolado)', mut(2,fn_extension='pg_net'), allow, 'g_evt_all_adjudicated')
a3=[dict(a) for a in allow]; a3[2]['fn_extension']='pg_graphql'
evt_neg('fn_extension pg_graphql→NULL (isolado)', live, a3, 'g_evt_all_adjudicated')
evt_neg('fn_extension pg_graphql→pg_net (isolado)', mut(2,fn_extension='pg_net'), a3, 'g_evt_all_adjudicated')
# G-2: NULL com semântica SQL
for k in ['owner','fn','fn_md5_lf','fn_secdef']:
    a4=[dict(a) for a in allow]; a4[4][k]=None; l4=mut(4,**{k:None})
    evt_neg(f'NULL em {k} nos dois lados não casa (= do SQL)', l4, a4, 'g_evt_all_adjudicated')
a5=[dict(a) for a in allow]; a5[1]['tags']=['CREATE EXTENSION']
evt_neg('evttags: allowlist com tag × LIVE NULL', live, a5, 'g_evt_all_adjudicated')
evt_neg('evttags: mesma lista em outra ordem', mut(1,tags=['B','A']), [dict(a,tags=['A','B']) if a['name']==live[1]['name'] else a for a in allow], 'g_evt_all_adjudicated')
# justificativa obrigatória (espelho do NULLIF(btrim(...)))
for lab,j in [('vazia',''),('só espaços','   '),('NULL',None)]:
    evt_neg(f'justificativa {lab} não adjudica', live, [dict(a,justification=j) for a in allow], 'g_evt_all_adjudicated')
evt_neg('trigger novo não adjudicado', live+[dict(live[0],name='evil_ddl_hook')], allow, 'g_evt_all_adjudicated')
login=dict(live[0],name='on_login_x',event='login')
evt_neg('evento login mesmo com linha na allowlist', live+[login], allow+[dict(login,justification='x')], 'g_evt_ddl_only')
evt_neg('evento login: allowlist não o torna adjudicado', live+[login], allow+[dict(login,justification='x')], 'g_evt_all_adjudicated')
ok,_=evt_gate(live+[dict(live[0],name='disabled_x',enabled='D')],allow,7); chk('EVT CONTROLE POSITIVO: trigger desabilitado (D) é inventariado sem efeito de gate', ok)
# G-3: incompletude do inventário (JOIN interno perde trigger cuja função não é encontrada)
cat=[dict(name=n,event=ev,enabled='O',tags=None,owner='SYNTH_owner',foid=i) for i,(n,ev) in enumerate(T03)]
procs={i:dict(fn='SYNTH.'+n+'()',fn_language='plpgsql',fn_owner='SYNTH_owner',fn_secdef=False,fn_config=None,fn_extension=None,fn_md5_lf='0'*32) for i,(n,ev) in enumerate(T03)}
inv=evt_join(cat,procs); ok,_=evt_gate(inv,allow,len(cat)); chk('EVT G-3 CONTROLE POSITIVO: catálogo 6 = inventário 6, adjudicado ⇒ passa', ok and len(inv)==6)
p2=dict(procs); del p2[3]; inv2=evt_join(cat,p2)
evt_neg('inventário incompleto: função não encontrada some do JOIN (catálogo 6 × evt 5)', inv2, allow, 'g_evt_inventory_complete', cc=len(cat))
cat2=cat+[dict(name='ghost_hook',event='ddl_command_end',enabled='O',tags=None,owner='x',foid=99)]
evt_neg('inventário incompleto: trigger adicional sem função resolvida (catálogo 7 × evt 6)', evt_join(cat2,procs), allow, 'g_evt_inventory_complete', cc=len(cat2))
# Envelopes autorizados não emitem comando da matriz de disparo (DDL/GRANT/COMMENT/SECURITY LABEL/SELECT INTO de SQL puro)
for f in ['2830H_E00_precheck_inventory.sql','2830H_E99_postcheck_residue.sql']:
    raw=re.sub(r"\$re\$.*?\$re\$","''",(H/f).read_text(encoding='utf-8'),flags=re.S); U=nostr(code(raw)).upper()
    chk(f'EVT: {f} (SQL puro) sem comando da matriz de disparo nem SELECT INTO', not re.search(r'\b(CREATE|ALTER|DROP|GRANT|REVOKE|COMMENT|SECURITY\s+LABEL|INTO|REINDEX|REFRESH|IMPORT)\b',U))
for f,tag in [('2830H_E01_section1_structural.sql','h2830_e01'),('2830H_E02_identity_terminal_D1_D5.sql','h2830_e02')]:
    body=nostr(code((H/f).read_text(encoding='utf-8')).split('$'+tag+'$')[1]).upper()
    chk(f'EVT: {f} (PL/pgSQL) sem comando da matriz de disparo (SELECT … INTO é atribuição PL/pgSQL)', not re.search(r'\b(CREATE|ALTER|DROP|GRANT|REVOKE|COMMENT|SECURITY\s+LABEL|REINDEX|REFRESH|IMPORT|EXECUTE)\b',body))


# ---------------------------------------------------------------------------
# CORRECTION-01 (G-5): roteiro reconciliado com o E00 vigente e a L4 revisada
# ---------------------------------------------------------------------------
rb=(H/'LIVE-STAGE1-RUNBOOK.md').read_text(encoding='utf-8')
_e00b=(H/'2830H_E00_precheck_inventory.sql').read_bytes()
_blob=hashlib.sha1(b'blob %d\x00'%len(_e00b)+_e00b).hexdigest(); _md5=hashlib.md5(_e00b).hexdigest()
_pc2=[l for l in rb.splitlines() if l.startswith('| PC-2 |')]
chk('ROTEIRO PC-2: exige o blob e o md5 do E00 VIGENTE (calculados deste arquivo)', len(_pc2)==1 and _blob in _pc2[0] and _md5 in _pc2[0], _blob+' '+_md5)
chk('ROTEIRO PC-2: nenhum hash antigo do E00 como critério (97410c3a, d00b7cec, a10ffd81, 470db26f)', len(_pc2)==1 and not re.search(r'97410c3a|d00b7cec|a10ffd81|470db26f',_pc2[0]))
_e00row=[l for l in rb.splitlines() if l.startswith('| **E00** — precheck |')]
chk('ROTEIRO §0: linha do E00 com blob/md5 vigentes e sem hash antigo', len(_e00row)==1 and _blob in _e00row[0] and _md5 in _e00row[0] and not re.search(r'97410c3a|a10ffd81',_e00row[0]))
chk('ROTEIRO §3.3: submissão do E00 cita o blob vigente', re.search(r'Submeter o \*\*conteúdo integral\*\* de `2830H_E00_precheck_inventory\.sql` \(blob `'+_blob+'`', rb) is not None)
chk('ROTEIRO: cabeçalho, PC-4 e P-1 citam o protocolo v1.5',
    '`LIVE-VALIDATION-PROTOCOL.md` **v1.5**' in rb and re.search(r'^\| PC-4 \|.*protocolo \*\*v1\.5\*\*',rb,re.M) and re.search(r'^\| P-1 \|.*protocolo v1\.5',rb,re.M))
_blocks=re.findall(r"```sql\n(.*?)```",rb,re.S)
_md5s=[hashlib.md5(b.encode()).hexdigest() for b in _blocks]
_decl={k:re.search(r'^\| \*\*'+k+r'\*\*.*?md5[^`]*`([0-9a-f]{32})`',rb,re.M) for k in ['L1','L3','L2','L4']}
chk('ROTEIRO: 4 blocos SQL (L1, L3, L2, L4)', len(_blocks)==4, str(len(_blocks)))
chk('ROTEIRO: md5 declarado em §0 = md5 do bloco (L1, L3, L2, L4)', all(_decl[k] and _decl[k].group(1) in _md5s for k in _decl), str(_md5s))
L4=_blocks[3] if len(_blocks)==4 else ''
_L4u=re.sub(r"'(?:[^']|'')*'","''",L4).upper()
chk('L4: um único statement, só leitura (sem DDL/DML/SET/INTO/DO)', _L4u.count(';')==1 and not re.search(r'\b(CREATE|ALTER|DROP|GRANT|REVOKE|COMMENT|INSERT|UPDATE|DELETE|MERGE|TRUNCATE|SET|INTO|DO|EXECUTE|CALL|COPY)\b',_L4u))
chk('L4: contagem e nomes lidos DIRETO do catálogo', 'count(*)' in L4 and 'jsonb_agg(e.evtname::text ORDER BY e.evtname) AS catalog_names' in L4 and L4.count('FROM pg_catalog.pg_event_trigger e')==2)
chk('L4: inventário com LEFT JOIN (trigger sem função não some) e fn_resolved', all(x in L4 for x in ['LEFT JOIN pg_proc p','LEFT JOIN pg_namespace n','LEFT JOIN pg_language l',"'fn_resolved',  p.oid IS NOT NULL"]))
chk('L4: completude e integridade na saída (catalog_count, inventory_count, inventory_complete, triggers_md5)',
    all("'"+k+"'" in L4 for k in ['catalog_count','catalog_names','inventory_count','inventory_complete','triggers_md5','triggers']))
chk('L4: exporta os 12 atributos pinados pelo E00', all("'"+k+"'" in L4 for k in ['name','event','tags','enabled','owner','fn','fn_language','fn_owner','fn_secdef','fn_config','fn_extension','fn_md5_lf']))


e99t=(H/'2830H_E99_postcheck_residue.sql').read_text(encoding='utf-8')
chk('E99: comentário declara TRÊS marcadores (não dois)', 'EXATAMENTE TRÊS marcadores' in e99t and 'EXATAMENTE dois' not in e99t)
chk('E99: md5 declarado como fidelidade da cópia, NÃO origem da rodada', 'NÃO' in e99t and 'prova de QUAL rodada' in e99t)
chk('E99: vinculação documental E00 → envelope → E99 explícita', 'VINCULAÇÃO DOCUMENTAL' in e99t and 'checked_at(E00) < submissão do envelope' in e99t)

bad=[r for r in res if not r[1]]
for n,ok,d in res: print(('PASS ' if ok else 'FAIL ')+n+(' '+d if d and not ok else ''))
print(f'TOTAL {len(res)} PASS {len(res)-len(bad)} FAIL {len(bad)}')
