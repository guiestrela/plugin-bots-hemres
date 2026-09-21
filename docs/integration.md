# Hermes runtime integration — PBH-011

## Estado

Investigação local concluída em 2026-09-21. Existe uma ponte real no Hermes Desktop:
`hermes serve` expõe gateway JSON-RPC 2.0 sobre WebSocket em `ws://127.0.0.1:<porta>/api/ws`.
A integração PBH ainda não foi implementada nem exercitada end-to-end.

## Interface confirmada por fontes locais

- Gateway: `/api/ws`.
- Protocolo: JSON-RPC 2.0 delimitado por newline.
- Evento inicial: `gateway.ready`.
- Eventos de streaming: `message.delta`, `reasoning.delta`, `thinking.delta`.
- Métodos relevantes:
  - `profiles.list`
  - `profiles.get_asset`
  - `session.create`, `session.list`, `session.resume`, `session.history`, `session.status`
  - `prompt.submit`
  - `approval.respond`
  - `clarify.respond`, `sudo.respond`, `secret.respond`
  - `session.interrupt`

Fontes locais lidas na investigação: `tui_gateway/ws.py`, `tui_gateway/server.py`,
`tui_gateway/methods_profiles.py`, `tui_gateway/methods_prompt.py` e o código do
Desktop em `apps/desktop/src/plugins/hermes-bots/`.

## Schemas mínimos observados

### Listar bots/perfis

```json
{"jsonrpc":"2.0","id":1,"method":"profiles.list","params":{"include_sessions":false}}
```

A resposta contém `profiles` e `bot_mode_protocol`. Cada perfil pode conter `name`,
`display_name`, `description`, `model`, `provider`, `has_avatar`, `ui_meta` e referências
de sessão. Para um roster simples, `include_sessions` deve ser explicitamente `false`.

### Avatar sob demanda

```json
{"jsonrpc":"2.0","id":2,"method":"profiles.get_asset","params":{"name":"backend","asset":"avatar"}}
```

A resposta pode conter `found`, `mime`, `size` e `data` como data URL. Formatos observados:
PNG, JPEG e WebP. `profiles.set_asset` é escrita e não será usado pelo PBH sem autorização.

### Enviar uma delegação

```json
{"jsonrpc":"2.0","id":3,"method":"prompt.submit","params":{"session_id":"...","text":"..."}}
```

O método inicia uma execução e entrega eventos de streaming; não deve ser exposto na UI antes
de existir correlação, confirmação explícita, timeout, cancelamento, estado de entrega incerta
e tratamento de aprovação.

### Aprovação

```json
{"jsonrpc":"2.0","id":4,"method":"approval.respond","params":{"session_id":"...","choice":"allow|deny|...","all":false,"request_id":"..."}}
```

A UI deve exibir a aprovação e correlacioná-la a sessão/request antes de enviar qualquer resposta.
Segredos, sudo e credenciais não podem ser coletados pelo painel.

## Descoberta operacional

Foram observados backends locais gerenciados pelo Desktop em `127.0.0.1` com portas efêmeras.
`GET /api/health` respondeu 200 e `auth_required:false`; `/api/profiles` respondeu 401.
O caminho REST não será assumido como transporte do PBH. As portas não possuem descoberta pública
estável pelo Omarchy; o adapter deve receber uma URL autorizada ou usar mecanismo documentado do
Desktop, sem extrair tokens de arquivos privados.

`hermes serve --status` não reconheceu os processos gerenciados pelo Desktop, embora processos
`hermes ... serve --host 127.0.0.1 --port 0` tenham sido observados. Isso precisa ser tratado como
limitação operacional e validado durante a implementação.

## Decisão técnica

Usar o gateway WebSocket JSON-RPC como transporte do painel, não Rakabot/Rakazo, Hermes `peer` ou
CLI terminal. Rakabot (`ozz1ee-dev/omarchy-rakabot`, commit `cd9aff89ade51e52e0a661f96c9bbaf2cdfdd177`)
é apenas referência de arquitetura visual/watcher; seus endpoints `/rpc/...` e autenticação são
incompatíveis com Hermes.

## Próxima implementação autorizada

1. Adapter local restrito para conexão WebSocket e `profiles.list` com `include_sessions:false`.
2. Avatar sob demanda via `profiles.get_asset`.
3. Painel QML com lista/seleção e estados loading/erro/vazio.
4. Sessão por perfil e streaming antes de liberar delegação.
5. Aprovação, cancelamento, timeout e entrega incerta.
6. Testes unitários, teste de conexão somente leitura e revisão defensiva.

Nenhum prompt, delegação, aprovação ou alteração de perfil foi enviado nesta investigação.
