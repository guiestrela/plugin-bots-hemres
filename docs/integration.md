# PBH-002 — Integração Hermes: investigação e contrato proposto

Estado: investigação entregue para revisão do CTO; NÃO é contrato aprovado nem adaptador implementado.
Data da verificação: 2026-09-21, UTC-03:00.
Projeto: `/home/guiestrela/Work/Plugin Bots Hemres`.
Vault: `/home/guiestrela/OneDrive/Obsidian Vault/Projetos/Plugin Bots Hemres`.
Status oficial: `Tarefas.md`, editado pelo CTO.

## 1. Conclusão executiva

Há interfaces reais para o produto, sem inventar um endpoint de bots:

- Bots locais são perfis. `hermes profile list` funciona nesta instalação; não possui opção JSON no help consultado.
- Chat interativo documentado: `hermes -p <perfil> chat`. Para a conversa canônica existente, acrescentar `--continue "Bot Chat"`; apenas selecionar o perfil NÃO garante abrir a conversa canônica.
- Envio de texto suportado pela CLI: `chat --query-file PATH` ou `--query-file -` (stdin). Em TTY real, sem `-Q`/`--oneshot`, o texto inicial é enviado e a sessão permanece interativa. É envio real, não pré-preenchimento de rascunho.
- Integração programática documentada: gateway JSON-RPC via stdio ou WebSocket, com `session.resume`, `prompt.submit` e eventos de aprovação. `profiles.list` também é documentado no Desktop Plugin SDK.
- Avatar: o código instalado oferece `profiles.get_asset({name,asset:"avatar"})`; faces geométricas/blob não são necessariamente arquivos. Seus metadados ficam em `ui_meta["hermes-bots"]`, e o frontend do Hermes desenha a face. Não prometer reproduzir exatamente uma face apenas porque existe um perfil.
- Recomendação para o primeiro contrato: adaptador local, inventário e avatares somente leitura, abertura e delegação em terminal Hermes interativo. É a menor superfície sem gerir tokens nem implementar uma segunda UI de aprovações. A alternativa JSON-RPC é real e adequada se o CTO exigir envio em background e acompanhamento no popup; requer escopo e testes adicionais.

Não foram abertos chats nem enviados prompts de teste. Também não foi iniciado servidor/gateway. Nenhuma conclusão aqui equivale a E2E aprovado.

## 2. Evidência do ambiente

Executável localizado por `command -v hermes` e `readlink -f`:
`/home/guiestrela/.hermes/hermes-agent/venv/bin/hermes`.

Fonte instalada: `/home/guiestrela/.hermes/hermes-agent`.
`hermes --version`: v0.21.0 (2026.8.31), upstream c7c2df1a, local 29112bef.
`git rev-parse HEAD`: `29112bef099274229cadff79cdff7bf7b99c4b77`.
A instalação tem alterações históricas locais; não equiparar automaticamente à release upstream.

`hermes profile list` retornou estes identificadores reais:

- `default`
- `assistente-sistema`
- `backend`
- `cto`
- `frontend`
- `pentester`

A coluna Gateway mostrou `stopped`; isso é status do gateway de mensagens, NÃO prova que o Desktop/backend esteja offline ou que o bot esteja ocioso. O perfil ativo apareceu como backend. Não usar display name/alias (`hermes`, por exemplo) como identificador persistente de `default`. Diretórios ocultos ou removidos não devem aparecer como bots.

`git -C '/home/guiestrela/Work/Plugin Bots Hemres' status --short` retornou exit 128: pasta ainda não é repositório Git. Não foi executado git init.

## 3. Interfaces e classificação de estabilidade

### 3.1 CLI documentada — caminho preferido para abertura/envio interativo

Comandos ilustrativos, NÃO executados nesta investigação:

```text
hermes -p <id-validado> chat --cli --continue "Bot Chat" --no-restore-cwd
hermes -p <id-validado> chat --cli --continue "Bot Chat" --no-restore-cwd --query-file <arquivo-privado>
```

Requisitos:

1. Executar por array de argumentos, nunca shell concatenado. O terminal emulador deve receber executable + argv; o frontend deve confirmar o launcher efetivo em PBH-003.
2. CWD fixo e explícito, aprovado para o produto; não herdar diretório de downloads ou conteúdo de terceiros. `--no-restore-cwd` evita o diretório antigo da sessão, mas o diretório usado influencia regras e permissões; não tratá-lo como sandbox.
3. Sem `--create-if-missing`: ausência de Bot Chat deve produzir erro, não criar silenciosamente outra conversa. Se criação for desejada, é decisão separada do CTO.
4. Delegação só após confirmação de bot + texto + escopo. Abrir chat não deve acrescentar prompt.
5. Arquivo de prompt em diretório privado do usuário (`0700`), arquivo `0600`, criação exclusiva/sem seguir symlink, limite de tamanho, remoção controlada após consumo/saída. Não usar arquivo no vault ou argumentos de processo para conteúdo sensível. Stdin é suportado para chamadas não interativas, mas não presumir que redirecioná-lo mantenha o comportamento TTY.
6. Terminal real: o help diz que non-TTY, `-Q` ou `--oneshot` transformam em resposta única. Não adicionar esses flags por conveniência.
7. Proibidos `-z`, `--yolo`, `--accept-hooks` e mudanças de approvals para fazer o teste passar. `-z` informa bypass de aprovações no próprio help. Modo single-query também depende da política existente; ausência de `--yolo` não prova isolamento.
8. A política do perfil/sessão pode permitir ações automaticamente; não prometer que toda operação exigirá confirmação. Ao precisar provar uma política específica, fazer auditoria separada e consentida, sem exibir config completa.

Limitação: sucesso ao iniciar processo significa `launched`, não tarefa aceita/concluída. Não há recibo estruturado JSON de execução no help consultado. O resultado da tarefa permanece no chat; o popup pode informar apenas que abriu a interface. Para acompanhar conclusão de modo confiável, escolher JSON-RPC.

### 3.2 Gateway JSON-RPC — protocolo documentado, detalhes dependentes de versão

A documentação oficial de integração admite hosts externos via stdio/WebSocket. Não confundir com API OpenAI nem inventar Unix socket.

- Stdio: implementação `python -m tui_gateway.entry` no Python do Hermes, com JSON por linha; documentação aponta o módulo/protocolo. Esse entrypoint deve ser encapsulado e verificado por versão, não importar handlers no processo da UI.
- WebSocket: `/api/ws` pertence ao backend `hermes serve`/dashboard, NÃO ao `api_server` de mensagens. O help de serve confirma padrão loopback 127.0.0.1 e porta 9119, mas isso não identifica a porta de uma instância viva.
- NÃO iniciar nem importar o servidor para introspecção inocente: `tui_gateway/entry.py:422-452` registra heartbeat, agenda orphan sweep e dispara descoberta MCP. `session.resume` também pode inicializar agente, alterar estado e auto-continuar trabalho. Essas operações não são consultas sem efeitos.

Mensagens ilustrativas a usar apenas após autorização da implementação:

```json
{"jsonrpc":"2.0","id":"list-1","method":"profiles.list","params":{"include_sessions":false}}
{"jsonrpc":"2.0","id":"avatar-1","method":"profiles.get_asset","params":{"name":"backend","asset":"avatar"}}
{"jsonrpc":"2.0","id":"open-1","method":"session.resume","params":{"profile":"backend","session_id":"Bot Chat","omit_messages":true}}
```

Após resume, usar `result.session_id` (runtime) em `prompt.submit`, não o ID durável. `resumed`/`session_key` identificam a conversa persistente. Perfil deve permanecer associado a todos os IDs.

```json
{"jsonrpc":"2.0","id":"send-1","method":"prompt.submit","params":{"session_id":"<runtime-retornado>","text":"<texto-confirmado>"}}
```

O handler retorna `status:"streaming"` quando inicia thread; não é confirmação de conclusão. Consumir eventos de ciclo de vida e erro, `message.delta`, `message.complete`, `approval.request`, `clarify.request`, `sudo.request`, `secret.request`. Não decidir conclusão de tarefa apenas pela primeira mensagem final de um evento sem fechar o ciclo do turno. Se a UI não suporta aprovações/segredos, não ativar delegação autônoma; direcionar usuário à interface Hermes, sem solicitar segredos no popup.

`profiles.list` retorna `{profiles:[...], ...}`; linhas contêm name, path, is_default, model, provider, description, display_name, skill_count, ui_meta opcional e has_avatar. Projetar somente os campos necessários. `include_sessions:false` evita previews de conversa e o caminho que pode desarquivar Bot Chat recuperável (`methods_profiles.py:155-192`). Não executar o default como suposta consulta puramente read-only.

`profiles.get_asset` retorna `{found:false}` ou `{found:true,data:"data:image/...;base64,...",mime,size}`. É método real no código, mas o schema detalhado não foi identificado como contrato público versionado. Manter allowlist de `asset:"avatar"`; não repassar campo asset fornecido pelo frontend nem permitir paths arbitrários.

Erros observados em código: 4063 name ausente; 4064 perfil ausente; 5066 falha do asset; 4006 session_id ausente; 4007 sessão ausente; 5000 erro de DB/resume; -32700 JSON inválido no stdio. Tratar outros códigos genericamente, com mensagem sanitizada. Ocupação pode implicar política de fila/steer: não assumir que toda chamada busy é rejeitada. Proibir reenviar prompt automaticamente após timeout de entrega incerta.

### 3.3 SDK Desktop e deep links

`@hermes/plugin-sdk`, `host.request` e `host.profileRoutes` são documentados para plugins DENTRO do Hermes Desktop. Uma barra externa do Omarchy não recebe esse objeto gratuitamente. Reutilizá-lo exigiria plugin/ponte adicional explicitamente aprovada.

Código confirma deep links genéricos `hermes://open/<path>`, mas não foi verificado um deep link estável que selecione perfil + Bot Chat canônico. O help `hermes desktop` não oferece seletor de chat/perfil. Não entregar URLs inventadas como `hermes://bot/backend`. Abertura garantida por contrato proposto é terminal CLI; abertura exata no Desktop fica pendente de requisito/revisão.

### 3.4 Dados locais — fallback interno, não API pública

`hermes_cli/profiles.py` contém:

- regex ID `^[a-z0-9][a-z0-9_-]{0,63}$`;
- `list_profiles()` exclui perfis removidos e lê metadados/modelo;
- `list_profile_names()` é somente scan de nomes, mas não tem todas as exclusões de list_profiles: NÃO basta como roster definitivo;
- `profile.yaml` contém metadados de apresentação; `assets/avatar.png`, `.jpg`, `.webp` são candidatos de imagem.

Uma implementação pode, sob aprovação, usar adapter de leitura local de metadados com whitelist, versão suportada e paths confinados, sem abrir config.yaml, .env, auth.json ou state.db. Essa estratégia evita credenciais, servidores e previews, mas é acoplamento ao layout interno. A CLI `profile list` é alternativa pública para validar IDs; parse de tabela exige testes de compatibilidade (sem --json no help atual).

Não importar módulos Hermes livremente como se fossem biblioteca estável. Não fazer glob em todos os arquivos do HERMES_HOME. Rejeitar symlinks que escapem da raiz aprovada, nomes ocultos e perfis removidos. O perfil default mora na raiz, perfis nomeados em profiles/<id>; não usar HERMES_HOME do backend como se fosse raiz de todos os perfis.

## 4. Contrato PBH v1 proposto (entre UI e adaptador; não é API existente)

Transporte inicial sugerido: helper local por subprocesso, stdin/stdout JSON limitado, sem servidor HTTP. Operações somente allowlist. O frontend não recebe comandos shell, tokens, diretórios de perfil ou histórico de chat. Wrapper de terminal com argv fixo; nenhum launcher livre vindo do payload.

Envelope de pedido:

```json
{"version":1,"requestId":"<id-local>","operation":"listBots","params":{}}
```

Resposta: `{version:1,requestId,ok:true,result:...}` ou `{version:1,requestId,ok:false,error:{code,message,retryable}}`. requestId é correlação, NÃO idempotência fornecida pelo Hermes.

Operações:

| Operação | Entrada | Resultado | Efeito |
|---|---|---|---|
| listBots | {} | bots[], source, stale, warnings[] | somente leitura; sem abrir sessão |
| getAvatar | {botId} | imagem validada/cache ou fallback identificado | leitura de avatar allowlisted |
| openChat | {botId} | {state:"launched",surface:"terminal"} | abre chat existente; pode inicializar runtime Hermes |
| delegateTask | {botId,text,confirmationId} | {state:"launched",surface:"terminal"} | envia turno no terminal; exige confirmação humana prévia |

Bot normalizado:

```text
id: identificador canônico validado (default não vira hermes)
source: "local"
displayName: texto escapado; fallback id
role: texto opcional, truncado, sem markup executável
avatar: {kind:"image"|"fallback",ref?:opaqueId,label?:string}
capabilities: {openChat:boolean,delegateTask:boolean,trackCompletion:false}
availability: "unknown"|"unavailable" (sem inferir busy do Gateway stopped)
hidden: boolean (respeitar se metadado verificado)
```

Sem timestamp de atividade ou prévia de mensagens no MVP. `ref` é ID opaco, não URL arbitrária nem caminho enviado ao cliente. Imagens: png/jpeg/webp, assinatura e decodificação verificadas, limites de bytes/dimensões; não SVG/HTML, não download remoto automático. Ausência ou falha = fallback explícito, nunca avatar falsamente atribuído. Faces procedurais podem usar inicial/ícone identificado como fallback; reprodução exata exigirá escopo frontend próprio.

Limites propostos, ainda não aprovados: texto UTF-8 até 16 KiB, não vazio, sem NUL; avatar até 2 MiB e 1024x1024; saída JSON até 4 MiB; listagem timeout 5 s com cache stale identificado; spawn timeout 10 s não equivale a timeout do turno. Preservar texto literal, inclusive aspas, Unicode, quebras e `$(...)`; nunca reinterpretar como flags/slash commands locais. Confirmar comportamento do Hermes quanto a slash commands em primeiro prompt antes do aceite do envio.

Códigos PBH propostos: INVALID_REQUEST, INVALID_BOT_ID, BOT_NOT_FOUND, UNSUPPORTED_VERSION, HERMES_NOT_FOUND, CHAT_NOT_FOUND, TERMINAL_UNAVAILABLE, PERMISSION_DENIED, AVATAR_INVALID, TIMEOUT, DELIVERY_UNKNOWN, UPSTREAM_FAILURE. `retryable:false` para envio incerto; clique repetido bloqueado enquanto o mesmo envio está pendente. `confirmationId` local deve ser emitido após confirmação e consumido uma vez, não aceitar um booleano arbitrário como evidência.

## 5. Autenticação, permissões e proteção

MVP subprocesso local: sem novo token; fronteira é usuário Unix e permissões de filesystem. Isso NÃO isola de outros processos do mesmo usuário. Nenhuma leitura/cópia de credenciais é necessária pelo adaptador. Hermes usa suas próprias credenciais, internamente.

Se adotado WebSocket: usar endpoint explicitamente configurado, autenticação oficial e verificação de origem/host; nunca procurar token em logs/arquivos privados nem enviá-lo pela URL/log. Documentação descreve sessão autenticada e tickets single-use para Desktop remoto; adaptar o fluxo completo antes de declarar suporte. Não adicionar `--insecure`, não bindar em 0.0.0.0, não reutilizar ticket. Descobrir somente status HTTP não valida WebSocket nem autorização. Credencial de API Server é outra fronteira e não serve automaticamente para dashboard.

Se adotado stdio: não há token de rede, mas existe poder de execução do mesmo usuário. Inicialização com efeitos exige aprovação de escopo. Não herdar variáveis de outro perfil indiscriminadamente; usar seleção oficial de perfil e testar isolamento. Não expor config.set, cli.exec, criação/exclusão de perfil ou método JSON-RPC arbitrário pela ponte PBH.

Delegação dispara um agente com ferramentas reais e pode ter custo. Confirmação do envio não substitui aprovações de deploy/exclusão/etc. Nenhum teste real será disparado sem autorização específica.

Logs só com requestId, operação, botId validado, estado, duração e código sanitizado; sem prompts, respostas, previews, tokens ou dumps. Nada sensível no OneDrive.

## 6. Verificações executadas e limites

| Consulta | Resultado real |
|---|---|
| command -v / readlink -f hermes | executável acima |
| hermes --version | versão e commit acima; exit 0 |
| git -C <fonte Hermes> rev-parse HEAD | commit completo acima; exit 0 |
| hermes --help | famílias profile/chat/serve/desktop presentes; exit 0 |
| hermes profile --help; hermes profile list --help | list existe; sem JSON; exit 0 |
| hermes profile list | IDs reais apresentados na seção 2 |
| hermes chat --help | query-file, TTY semantics, continue, no-restore-cwd; exit 0 |
| hermes desktop --help | launch/build; não seletor de chat; exit 0 |
| hermes serve --help | loopback/porta/auth descritos; não iniciou servidor; exit 0 |
| curl --fail --silent --show-error --max-time 25 https://hermes-agent.nousresearch.com/docs/llms.txt | índice oficial completo recuperado; exit 0 |
| read_file/search_files no código local | parâmetros/retornos e efeitos documentados acima |
| git status no projeto | exit 128, não é repo Git |

Falhas reais: web_extract de developer-guide/programmatic-integration e desktop-plugin-sdk retornou 403 do provedor de extração; Bot Mode/índice vieram parcialmente. browser_exec falhou ao iniciar daemon. Uma tentativa python3 -c para HTTP foi bloqueada pelo gate de execução e NÃO rodou; não se contornou política. curl simples recuperou o índice público. Detalhes das páginas de desenvolvimento foram conferidos no Markdown da instalação local, não declarados como fetch integral atual dessas páginas.

Não validado: conteúdo real dos avatares, runtime JSON-RPC, autenticação WS, deep link canônico Desktop, envio/resultado de tarefa, diálogo de aprovação interativo, concorrência com Bot Chat já ocupado, isolamento final do launcher e política de symlinks. Não houve leitura de .env/auth.json/config pessoal nem histórico privado.

## 7. Fontes verificáveis

Documentação oficial (índice vivo consultado):
- https://hermes-agent.nousresearch.com/docs/llms.txt
- https://hermes-agent.nousresearch.com/docs/user-guide/bot-mode
- https://hermes-agent.nousresearch.com/docs/developer-guide/programmatic-integration
- https://hermes-agent.nousresearch.com/docs/developer-guide/desktop-plugin-sdk
- https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard

Arquivos relativos à fonte instalada `/home/guiestrela/.hermes/hermes-agent`, commit fixado na seção 2:
- `website/docs/user-guide/bot-mode.md`: 12-26 (identidade e chat), 58-68 (avatar), 93-118 (DM/erros), 178-189 (CLI).
- `website/docs/developer-guide/programmatic-integration.md`: 11-17, 37-95 (protocolos/eventos).
- `website/docs/developer-guide/desktop-plugin-sdk.md`: 551-574 (rotas/perfis); documentação menciona preferred_session_ids que não deve ser pressuposto nesta versão do handler. Usar detecção de campos, não confiança cega em docs.
- `hermes_cli/profiles.py`: 51, 434-450, 1029-1102 (validação/inventário).
- `tui_gateway/methods_profiles.py`: 22-28, 155-192, 254-328, 1107-1145 (roster/assets).
- `tui_gateway/methods_session.py`: 374-413 e 1084-1101 (resume e IDs).
- `tui_gateway/methods_prompt.py`: 287-297, 1028-1048 (texto e início de streaming).
- `tui_gateway/entry.py`: 422-452, 454-467, 486-510 (efeitos de startup e formato).
- `apps/desktop/src/plugins/hermes-bots/types.ts`: 54-99; `profile-ops.ts`: 153-208 (metadados e avatars).
- `apps/desktop/src/lib/hermes-open-target.ts`: 9-12, 68-108 (deep links genéricos).
- `tools/approval.py`: 294-316 (contexto single-query).

## 8. Próximas decisões solicitadas ao CTO (PBH-004)

1. Aprovar MVP CLI/terminal interativo ou exigir JSON-RPC com UI de aprovações e conclusão. Não são experiências equivalentes.
2. Aprovar inventário/avatar por layout interno somente leitura ou exigir backend RPC para roster. Em ambos, fallback deve ser explícito e versão tratada.
3. Confirmar CWD, terminal launcher e localização privada dos prompts/cache com frontend; sem ativar barra nesta fase.
4. Depois do contrato, autorizar implementação PBH-005 e testes isolados: argv/injeção, schemas/limites, symlinks, perfil removido/renomeado, imagem inválida, ausência de Bot Chat, timeout incerto, duplo clique, segredo nos logs, TTY versus non-TTY. Um teste real de envio exige autorização adicional específica.

Não alterar Plano/Tarefas para justificar esta proposta. A investigação está pronta para revisão; produto não implementado, testado E2E ou publicado.
