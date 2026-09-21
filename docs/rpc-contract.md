# PBH RPC Contract v1 — Plugin QML ↔ Hermes

**Status:** proposta técnica concreta para revisão do CTO; não é uma API existente do Hermes e não autoriza ativação, envio de prompt ou início de gateway. A decisão de produto para v1 é **painel QML integral**: envio, respostas, streaming e aprovações devem ocorrer no painel, sem terminal como superfície do usuário.

**Escopo:** contrato entre o `bar-widget` QML e um adaptador local seguro. O adaptador é o único componente que fala com Hermes. O QML não recebe comandos shell, caminhos de perfil, histórico, tokens ou credenciais.

**Evidências de base:** `docs/integration.md`, `docs/ui-discovery.md` e o código instalado do Hermes em `/home/guiestrela/.hermes/hermes-agent`, versão observada `v0.21.0`, commit local `29112bef099274229cadff79cdff7bf7b99c4b77`. Campos ou comportamentos não confirmados no código local estão explicitamente marcados como pendentes.

## 1. Transporte e fronteiras

### 1.1 Transporte recomendado: stdio local, uma linha JSON por mensagem

O adaptador deve ser iniciado como subprocesso local, com stdin/stdout conectados ao QML por uma ponte aprovada pelo host. Cada mensagem é um objeto JSON UTF-8 terminado por `\\n`; stdout contém somente respostas/eventos JSON. Logs vão para stderr ou para o logger do host, nunca para stdout.

Motivos: a integração documentada do TUI Gateway suporta JSON-RPC sobre stdio; não exige porta nem token de rede; evita inventar um endpoint HTTP/Unix socket. O processo ainda tem o poder do usuário Unix e, portanto, **não é sandbox**.

O adaptador pode, internamente, encapsular o TUI Gateway via `python -m tui_gateway.entry`, mas deve verificar a versão e falar com ele por processo separado. Não importar handlers do Hermes no processo QML/adaptador.

### 1.2 WebSocket não é o transporte v1

WebSocket fica reservado para uma revisão posterior. A documentação identifica `/api/ws` como backend de `hermes serve`/dashboard, com padrão loopback `127.0.0.1:9119`, mas isso não identifica a porta de uma instância viva nem substitui autenticação. Uma implementação futura só pode usar endpoint explicitamente configurado, autenticação oficial, verificação de host/origem e tickets single-use quando aplicável. É proibido descobrir token em arquivos/logs, colocá-lo na URL, usar `--insecure` ou bindar em `0.0.0.0`.

### 1.3 Separação de protocolos

Há duas camadas:

1. **PBH v1 (QML ↔ adaptador):** envelope abaixo, operações `listBots`, `getAvatar`, `delegateTask` e eventos PBH. `openChat` é somente compatibilidade/fora do fluxo principal e não abre terminal.
2. **Hermes TUI Gateway (adaptador ↔ Hermes):** JSON-RPC 2.0 documentado, com métodos como `profiles.list`, `profiles.get_asset`, `session.resume`, `prompt.submit` e respostas a prompts bloqueantes.

O QML nunca envia método Hermes arbitrário. O adaptador mantém uma allowlist fixa.

**Bloqueio de integração:** a documentação e o código local confirmam os métodos/eventos do Gateway, mas o runtime JSON-RPC, o encaminhamento integral de respostas e o diálogo interativo não foram executados/validados. Portanto, este documento não declara suporte implementado: até uma ponte aprovada e testes offline/E2E autorizados confirmarem esses pontos, `delegateTask`, streaming e prompts interativos devem ser anunciados como `unsupported` (não como `accepted`). Se a implementação disponível não fornecer todos esses eventos e respostas com segurança pelo canal local, o mínimo necessário é uma ponte allowlisted QML↔Gateway que (a) correlacione sessões runtime, (b) encaminhe deltas/eventos na ordem, (c) exponha somente aprovação/clareza redigidas e escolhas seguras, (d) recuse segredo/sudo sem capturar credenciais e (e) devolva `unsupported` para qualquer capacidade não verificável. Não usar terminal como fallback de v1.

## 2. Envelope PBH v1

### 2.1 Pedido

```json
{
  "version": 1,
  "requestId": "req-01J...",
  "operation": "listBots",
  "params": {}
}
```

Regras:

- `version` é o inteiro `1`.
- `requestId` é uma string não vazia, única enquanto o pedido estiver pendente, limitada a 128 bytes UTF-8.
- `operation` é uma operação da allowlist; nomes desconhecidos falham.
- `params` é objeto; ausente equivale a `{}` apenas para operações que não exigem parâmetros.
- Não aceitar comando, executable, argv, cwd, path, URL, token, script ou método Hermes vindo do payload.

### 2.2 Resposta de sucesso

```json
{
  "version": 1,
  "requestId": "req-01J...",
  "ok": true,
  "result": {}
}
```

### 2.3 Resposta de erro

```json
{
  "version": 1,
  "requestId": "req-01J...",
  "ok": false,
  "error": {
    "code": "BOT_NOT_FOUND",
    "message": "Bot não encontrado.",
    "retryable": false
  }
}
```

`message` é sanitizada e adequada para exibição. Não incluir prompt, resposta do agente, traceback, token, caminho privado ou comando completo. Campos adicionais não são necessários para v1; se houver `details`, ele deve ser não sensível e versionado. Capacidades usam `true`, `false` ou `unsupported`; `unsupported` significa que a implementação não pode ser verificada com segurança e não pode ser usada como fallback.

### 2.4 Evento assíncrono

```json
{
  "version": 1,
  "event": "task.accepted",
  "eventId": "evt-01J...",
  "requestId": "req-01J...",
  "botId": "backend",
  "taskId": "opaque-task-id",
  "payload": {}
}
```

`requestId` correlaciona o evento ao pedido que iniciou a operação. `eventId` é opaco, único por execução do adaptador e serve para deduplicar entrega. Eventos sem `requestId` só podem ser eventos de ciclo de vida do adaptador.

## 3. Operações PBH permitidas

### 3.1 `listBots`

Pedido: `params: {}`.

O adaptador usa `profiles.list` com `include_sessions:false`, sem abrir sessão nem incluir prévias. O resultado é:

```json
{
  "bots": [
    {
      "id": "backend",
      "source": "local",
      "displayName": "Backend",
      "role": "",
      "avatar": {"kind": "image", "ref": "opaque-avatar-ref", "label": "Avatar de Backend"},
      "capabilities": {"openChat": false, "delegateTask": "unsupported", "streaming": "unsupported", "approval": "unsupported", "trackCompletion": "unsupported"},
      "availability": "unknown",
      "hidden": false
    }
  ],
  "source": "hermes-profiles",
  "stale": false,
  "warnings": []
}
```

`id` é o identificador canônico validado; não derivar de `displayName` e não transformar `default` em `hermes`. `availability` só pode ser `unknown` ou `unavailable` no v1: `Gateway stopped` não prova que um bot está offline/ocioso. Lista vazia confirmada é diferente de erro de descoberta.

Não retornar timestamp de atividade, preview de conversa ou path de perfil no MVP. Perfis ocultos/removidos não aparecem. Falha parcial de avatar não falha a lista; retorna `avatar.kind:"fallback"` e warning sanitizado.

### 3.2 `getAvatar`

Pedido:

```json
{"botId":"backend"}
```

O adaptador valida `botId` contra o roster atual e só chama `profiles.get_asset` com `asset:"avatar"`. O resultado é uma referência opaca de cache ou imagem inline já validada:

```json
{"botId":"backend","avatar":{"kind":"image","ref":"opaque-avatar-ref","mime":"image/png","size":12345}}
```

Ou:

```json
{"botId":"backend","avatar":{"kind":"fallback","label":"Avatar não disponível"}}
```

A API Hermes observada retorna `{found:false}` ou `{found:true,data:"data:image/...;base64,...",mime,size}`. O adaptador não expõe essa data URL ao QML sem validar assinatura/decodificação. Somente PNG, JPEG e WebP; máximo proposto 2 MiB e 1024×1024. Nunca SVG/HTML, URL remota, traversal ou symlink fora da raiz permitida.

### 3.3 `openChat`

Pedido:

```json
{"botId":"backend"}
```

`openChat` não faz parte do fluxo principal de v1 e não é uma autorização para abrir terminal. Mantém-se apenas como operação de compatibilidade futura, desabilitada por padrão:

```json
{"state":"unsupported","reason":"PANEL_ONLY_V1"}
```

O contrato não promete deep link, seleção de perfil no Desktop ou abertura de `Bot Chat`: nenhum caminho estável foi verificado. Se algum consumidor solicitar a operação, o adaptador deve retornar `unsupported`, sem lançar processo, abrir terminal ou criar sessão.

### 3.4 `delegateTask`

Pedido:

```json
{
  "botId":"backend",
  "text":"Texto literal da tarefa",
  "confirmationId":"confirm-01J..."
}
```

Validação: destinatário, texto não vazio após validação de presença, UTF-8 até 16 KiB, sem NUL; preservar aspas, Unicode, quebras e `$(...)` como texto literal. `confirmationId` deve ter sido emitido pelo adaptador após confirmação explícita do usuário exibindo bot, texto e escopo. Booleano `confirmed:true` não é aceito. O ID é consumido uma vez e expira quando usado ou em até 10 minutos.

O texto não vai em argv. A única rota de v1 é a ponte QML↔Gateway autorizada, com `session.resume` e `prompt.submit` allowlisted; o QML recebe a resposta e os eventos pelo mesmo contrato. Não usar launcher CLI/terminal como fallback, nem declarar aceite a partir de spawn. Para um adaptador TUI Gateway autorizado, `prompt.submit` retorna `{status:"streaming"}`; isso é início de streaming, não conclusão.

Resposta imediata quando a ponte estiver verificada:

```json
{"state":"streaming","surface":"qml","taskId":"opaque-task-id","completionTracked":true}
```

Enquanto a ponte, o runtime e o fechamento do turno não estiverem verificados:

```json
{"state":"unsupported","surface":"qml","reason":"RPC_RUNTIME_UNVERIFIED"}
```

`accepted` só pode ser usado quando o upstream confirmar o recebimento; `streaming` não é conclusão. `surface` em v1 é sempre `qml` quando suportado, nunca `terminal`.

Não oferecer Cancelar execução no QML: a capacidade não está no contrato PBH v1. Se a entrega ou a resposta da ponte ficar incerta, retornar `DELIVERY_UNKNOWN` com `retryable:false` e não reenviar automaticamente.

## 4. Ciclo de vida e streaming Hermes

### 4.1 Ciclo do adaptador

1. `starting`: validar versão, limites, diretório temporário privado e allowlist.
2. `ready`: enviar evento `{event:"adapter.ready",payload:{protocolVersion:1,transport:"stdio"}}` somente depois de o canal estar utilizável.
3. `requesting`: correlacionar `requestId`; rejeitar duplicata ainda pendente.
4. `streaming`: para delegação pelo Gateway, consumir eventos Hermes até fechamento do turno e entregá-los ao painel QML; se isso não estiver verificado, permanecer `unsupported`.
5. `idle`: nenhuma solicitação pendente.
6. `stopping`/`stopped`: EOF, falha do processo ou encerramento explícito; pedidos pendentes tornam-se `ADAPTER_UNAVAILABLE` ou `DELIVERY_UNKNOWN` conforme o ponto de entrega.

Abrir/inicializar `session.resume` pode alterar estado, criar runtime e auto-continuar trabalho; não tratá-lo como consulta read-only. Após `session.resume`, usar `result.session_id` (runtime) para `prompt.submit`; manter perfil associado a todos os IDs. `resumed`/`session_key` identificam a conversa persistente.

### 4.2 Eventos de turno

Quando o transporte Hermes for usado e a capacidade correspondente estiver confirmada, o adaptador normaliza estes eventos:

- `message.delta`: fragmento incremental de mensagem; `payload` pode conter apenas texto incremental.
- `message.complete`: mensagem encerrada; contém texto/status conforme o upstream; não equivale sozinho a conclusão operacional.
- `tool.start`, `tool.progress`, `tool.complete`: atividade de ferramenta; QML recebe estado resumido, sem argumentos/saídas sensíveis.
- `status.update`: estado textual sanitizado.
- `task.error`: falha terminal do turno.
- `task.complete`: só emitir se o upstream fechar o turno e o adaptador puder afirmar encerramento; nunca inferir apenas do primeiro “final”.

A ponte deve preservar a ordem relativa dos eventos não-streaming. `message.delta` pode ser fragmentado e não deve ser usado como recibo.

## 5. Aprovações, clarify, secret e sudo

O TUI Gateway documenta `approval.request`, `clarify.request`, `sudo.request`, `secret.request` e eventos de expiração correspondentes; os métodos de resposta são `approval.respond`, `clarify.respond`, `sudo.respond` e `secret.respond`. Isso é evidência de protocolo documentado, não suporte PBH já verificado.

### 5.1 Regra de capacidade

O painel QML v1 é a superfície única e suporta somente interação segura e redigida:

- `approval.request` pode ser exibido no painel apenas com representação já redigida e escolhas allowlisted (`once`, `session`, `always`, `deny`). A aprovação deve ser confirmada no painel e encaminhada pelo adaptador; o adaptador não reconstrói comando bruto.
- `clarify.request` pode ser exibido no painel quando a pergunta e as escolhas forem não sensíveis; respostas de texto devem ser explicitamente confirmadas e associadas ao `request_id` exato. Pergunta não verificável ou potencialmente secreta retorna `unsupported`.
- `secret.request` e `sudo.request` são recusados/encaminhados para uma interface Hermes autorizada, sem popup de credencial, sem captura, armazenamento, eco ou log de senha/token/valor secreto. O PBH não chama `secret.respond` nem `sudo.respond` com valor fornecido pelo QML.
- `delegateTask` só fica habilitado se o adaptador declarar suporte verificado para streaming e para aprovação/clareza segura. Caso contrário, responde `state:"unsupported"` com `INTERACTIVE_APPROVAL_UNSUPPORTED` ou `RPC_RUNTIME_UNVERIFIED`, antes de enviar.
- Qualquer capacidade não verificável é `unsupported`; não inferir suporte porque o método upstream está documentado.

### 5.2 Envelope de eventos bloqueantes

Normalizado pelo adaptador:

```json
{
  "version":1,
  "event":"approval.request",
  "eventId":"evt-01J...",
  "requestId":"req-01J...",
  "botId":"backend",
  "payload":{
    "approvalRequestId":"opaque-upstream-request-id",
    "choices":["once","session","always","deny"],
    "summary":"Aprovação necessária (detalhes redigidos).",
    "expiresAt":null
  }
}
```

Respostas internas do adaptador, nunca disparadas automaticamente pelo QML:

```json
{"method":"approval.respond","params":{"session_id":"runtime","request_id":"opaque-upstream-request-id","choice":"deny"}}
```

```json
{"method":"clarify.respond","params":{"session_id":"runtime","request_id":"opaque-upstream-request-id","answer":"resposta do usuário"}}
```

`sudo.respond` e `secret.respond` não fazem parte da ponte PBH v1: são recusados/encaminhados sem payload de credencial.

Para `clarify.request`, preservar `question`, `choices`, `multi_select` e, em lote, `questions:[{qid,question,choices,multi_select}]`. Associar respostas ao `request_id` exato. Em `*.expire`, limpar apenas o pedido correspondente; não responder novamente nem retentar a tarefa. O código observado aceita algumas respostas tardias, mas isso não torna seguro exibir segredo no painel. Após `*.expire`, limpar somente o pedido correspondente; não responder novamente nem retentar.

## 6. Erros

### 6.1 Códigos PBH

| Código | Significado | Retry automático |
|---|---|---:|
| `INVALID_REQUEST` | envelope, versão, operação ou parâmetro inválido | não |
| `UNSUPPORTED_VERSION` | versão diferente de 1 | não |
| `INVALID_BOT_ID` | ID ausente/malformado | não |
| `BOT_NOT_FOUND` | perfil não está no roster validado | não |
| `CHAT_NOT_FOUND` | `Bot Chat` não existe; não criar implicitamente | não |
| `HERMES_NOT_FOUND` | executável ou fonte aprovada indisponível | após correção |
| `ADAPTER_UNAVAILABLE` | subprocesso/canal indisponível | manual |
| `RPC_RUNTIME_UNVERIFIED` | runtime/ponte/eventos necessários para o painel não foram verificados | não |
| `PERMISSION_DENIED` | permissão/escopo negado | não |
| `INTERACTIVE_APPROVAL_UNSUPPORTED` | painel não pode tratar aprovação/secret/sudo/clarify | não |
| `AVATAR_INVALID` | imagem ausente, inválida ou fora do limite | não |
| `TIMEOUT` | nenhuma entrega foi confirmada dentro do timeout | depende da operação |
| `DELIVERY_UNKNOWN` | a ponte pode ter recebido o texto, mas o recibo não foi confirmado | **não** |
| `UPSTREAM_FAILURE` | Hermes retornou erro não mapeado | conforme `retryable` sanitizado |
| `DUPLICATE_REQUEST` | mesma operação ainda pendente ou já consumida | não |
| `LIMIT_EXCEEDED` | tamanho, quantidade ou duração acima do limite | não |

### 6.2 Erros JSON-RPC upstream

O adaptador preserva internamente códigos do Gateway, mas não os expõe como contrato QML. Códigos observados incluem `-32700` parse error, `4063` name ausente, `4064` perfil ausente, `5066` falha de asset, `4006` session_id ausente, `4007` sessão ausente e `5000` erro de DB/resume. Todos os demais são mapeados para `UPSTREAM_FAILURE` com mensagem sanitizada.

## 7. Deduplicação, concorrência e limites

- `requestId` correlaciona; não fornece idempotência por si só.
- O adaptador mantém uma tabela em memória por `(operation, botId, confirmationId)` e rejeita clique repetido enquanto o envio estiver pendente.
- Um `confirmationId` é single-use. Reutilização dá `DUPLICATE_REQUEST`.
- Para `delegateTask`, nunca reenviar após timeout de entrega incerta. O painel deve mostrar estado desconhecido, sem sugerir que um terminal foi aberto.
- Um único `delegateTask` pendente por adaptador no v1; `openChat` não pode acrescentar prompt e permanece `unsupported`.
- `listBots`: timeout proposto 5 s; cache pode ser servido como `stale:true` com warning explícito.
- Inicialização/spawn: timeout proposto 10 s; isso não é timeout do turno Hermes.
- Texto: UTF-8, máximo 16 KiB, não vazio, sem NUL.
- Avatar: máximo 2 MiB, 1024×1024, PNG/JPEG/WebP.
- Linha/envelope PBH: máximo 4 MiB; exceder dá `LIMIT_EXCEEDED` sem processar prefixo.
- `requestId`, `eventId`, `taskId`, `confirmationId` são strings opacas; não interpretar como path, URL ou comando.
- QML preserva rascunho somente em memória; fechar/hot reload não reenvia. O adaptador não persiste prompt em vault, config ou logs.

## 8. Segurança e privacidade

1. Executar subprocessos por array de argumentos fixos; nunca shell concatenado.
2. CWD explícito aprovado; `--no-restore-cwd` evita restaurar diretório antigo, mas não é sandbox.
3. Não ler/copiar `.env`, `auth.json`, `config.yaml` completo, `state.db` ou credenciais. Hermes usa as próprias credenciais internamente.
4. Não expor `config.set`, `config.get`, `cli.exec`, criação/exclusão de perfil, `reload.env`, método arbitrário, histórico ou previews ao QML.
5. Validar IDs e paths no adaptador; rejeitar nomes ocultos, perfis removidos, symlinks que escapem da raiz aprovada e assets não allowlisted.
6. Não renderizar HTML/Markdown remoto; dados de nomes, funções e mensagens entram como texto simples escapado.
7. Logs somente com `requestId`, operação, `botId` validado, estado, duração e código. Nunca prompt, resposta, avatar inline, senha, secret, token, argv completo ou traceback.
8. Plugins QML são código não sandboxed no processo do desktop. Minimizar dependências e não presumir que a ponte de serviço da Glass Bar é singleton; a primeira implementação deve ser um `bar-widget` sem serviço global obrigatório.
9. Aprovação de envio não substitui aprovações de deploy, exclusão, sudo ou outras ações das ferramentas Hermes.
10. Não ativar `-z`, `--yolo`, `--accept-hooks`, bypass de approval ou configuração equivalente para testes.

## 9. Matriz de testes para aprovação do contrato

Os testes abaixo são offline/fixture por padrão e não enviam prompt real. Um teste E2E de envio exige autorização separada, destinatário e texto acordados.

### Protocolo e estado

- envelope válido, JSON inválido, objeto não-JSON, versão desconhecida e operação desconhecida;
- `requestId` ausente, repetido, excessivo e colisão entre operações;
- resposta/evento fora de ordem, evento duplicado e reconexão/EOF;
- limite de 16 KiB, 4 MiB, Unicode, quebras, aspas, NUL e texto vazio;
- `listBots` com lista vazia, erro de descoberta, perfil removido/renomeado, ID `default` e cache stale;
- `getAvatar` com ausência, PNG/JPEG/WebP válidos, imagem inválida, dimensão/tamanho excessivos, SVG/HTML, traversal e symlink.

### Segurança da ponte de envio

- nenhum launcher CLI/terminal como superfície ou fallback;
- método Hermes sempre allowlisted; nenhum método arbitrário, comando, argv, cwd ou flag vindo do QML;
- prompt nunca em argv, logs, vault, `shell.json` ou stdout de diagnóstico;
- sessão runtime retornada por `session.resume` associada ao perfil correto;
- nenhum acesso a `.env`, `auth.json`, configuração completa, histórico privado ou token.

### Entrega e deduplicação

- confirmação humana gera `confirmationId`; booleano falso e replay são rejeitados;
- duplo clique enquanto pendente, timeout de ponte, EOF após possível entrega e `DELIVERY_UNKNOWN` sem retry;
- distinção entre `unsupported`, `accepted`, `streaming`, `complete` e erro; nunca `launched` para superfície de v1;
- `session.resume` por título `Bot Chat`, uso do runtime `session_id` retornado e ausência de criação implícita.

### Prompts bloqueantes e streaming

- fixture para `message.delta`/`message.complete`/`tool.*` preservando ordem;
- `approval.request` com comando redigido e escolhas permitidas;
- `clarify.request` simples e em lote, `multi_select`, resposta ao `request_id` correto e `clarify.expire`;
- `secret.request`/`sudo.request` recusados no painel sem vazamento em UI/logs;
- expiração, resposta tardia e pedido cancelado não causam reenvio;
- `message.complete` isolado não é tratado como conclusão de tarefa.

### QML/host, depois da implementação

- validação do manifesto com `omarchy plugin validate` sem instalar/ativar;
- `qmllint` e `qmlformat` sem escrita, em harness separado e fora da barra ativa;
- teclado, foco, Esc sem envio, texto ampliado, nomes longos, tema claro/escuro, múltiplos monitores e hot reload;
- coexistência com Glass Bar e Hermes Deck, sem duplicação de serviço, polling ou envio.

## 10. Fora do v1 e limitações conhecidas

- O launcher CLI/terminal não é superfície nem fallback de v1; sua limitação de conclusão permanece relevante apenas para uma integração futura fora deste contrato.
- Não há cancelamento real de execução no contrato PBH.
- WebSocket, autenticação remota e deep link canônico Desktop não estão aprovados.
- A reprodução exata de faces geométricas/blob depende de metadados `ui_meta["hermes-bots"]` e frontend Hermes; ausência de arquivo de avatar exige fallback explícito.
- Não foram validados runtime JSON-RPC, autenticação WS, envio real, diálogo interativo, concorrência com `Bot Chat` ocupado, ponte QML integral, isolamento final do adaptador ou política final de symlinks; por isso essas capacidades permanecem `unsupported` até verificação.
- A documentação instalada descreve o protocolo, mas detalhes podem mudar com a versão local; o adaptador deve fazer detecção de campos e rejeitar incompatibilidades, não assumir que toda documentação futura é compatível.

A implementação do adaptador, o plugin QML, a ativação de plugin, o início de gateway e qualquer envio real permanecem fora deste artefato.
