# Kamailio Softswitch

Este diretório documenta o uso do Kamailio como camada Softswitch/SIP edge do mnscloud.

Para WebRTC/SIP over WebSocket, certificados WSS por domínio e rtpengine, use o
conector dedicado `mnscloud-kamailio-webrtc`. Este módulo continua sendo o
contrato Kamailio/softswitch genérico.

## Modelo

- O servidor físico mantém a URL base da API em `/etc/mnscloud/softswitch/api.base`.
- O servidor físico mantém UUID local em `/etc/mnscloud/softswitch/node.uuid`.
- O servidor físico mantém token local em `/etc/mnscloud/softswitch/api.token`.
- Esse UUID é vinculado ao cadastro `VoipSoftswitchServer.VsrNodeUUID`.
- O hash do token é salvo em `VoipSoftswitchServer.VsrApiTokenHash`.
- Cada requisição runtime enviada ao mnscloud usa `node_uuid` e `Authorization: Bearer <token>` para validar o servidor.
- A API usa cache curto para a identidade do servidor, reduzindo IO por chamada sem perder revogação operacional.

## Cadastros

- `VoipSoftswitchProvider`: catálogo do provider/plataforma, com engines `kamailio`, `opensips`, `sippulse`, `vsc` e `custom`.
- `VoipSoftswitchServer`: servidores autorizados a consultar runtime.
- `VoipSoftswitchAccount`: vínculo tenant/domínio/customer/provider/server usado para autorizar domínios e assinantes.

## Endpoints Runtime

Os endpoints internos ficam em:

- `POST /api/v1/softswitch/kamailio/heartbeat`
- `POST /api/v1/softswitch/kamailio/bootstrap`
- `POST /api/v1/softswitch/kamailio/auth`
- `POST /api/v1/softswitch/kamailio/route`
- `POST /api/v1/softswitch/kamailio/accounting`

O `node_uuid` pode ir via query string ou header `X-Softswitch-Node-UUID`. O token é
gerado pelo instalador, enviado como `Authorization: Bearer <token>` no bootstrap e
nas consultas runtime, e somente o hash fica salvo no banco.

## Instalação

Execute:

```bash
bash scripts/install-kamailio-softswitch.sh
```

O instalador:

- solicita a URL base da API na primeira execução e salva em `/etc/mnscloud/softswitch/api.base`;
- configura o repositório oficial Kamailio 6.1.x antes da instalação;
  - Debian 12/13: `http://deb.kamailio.org/kamailio61` com keyring `/usr/share/keyrings/kamailio.gpg`;
  - Debian usa pinning em `/etc/apt/preferences.d/kamailio` para preferir os pacotes 6.1.x oficiais em vez dos pacotes antigos da distribuição;
  - Rocky 8/9: `https://rpm.kamailio.org/rocky/<major>/6.1/6.1/<arch>/`;
- instala Kamailio e ferramentas de troubleshooting (`sngrep`, `tcpdump`, `ngrep`, `ping`, `mtr`, `jq`, etc.);
- cria ou reaproveita `/etc/mnscloud/softswitch/node.uuid`;
- cria ou reaproveita `/etc/mnscloud/softswitch/api.token`;
- tenta vincular o node UUID via API bootstrap usando hostname, IPv4 privado e IPv4 público descoberto;
- não executa SQL direto nem instala cliente MariaDB para vincular o node UUID;
- faz backup do `/etc/kamailio/kamailio.cfg` original como `.bkp`;
- gera um `kamailio.cfg` com autenticação SIP digest para REGISTER e INVITE de assinantes;
- salva contatos com `registrar/usrloc` em memória local;
- consulta `/route` na API para chamadas de saída quando o destino não está registrado localmente.
- grava o Bearer token local no `kamailio.cfg` para autenticar as chamadas runtime contra a API.

O arquivo gerado usa `http_client` para chamadas runtime síncronas de baixa latência contra a API.
REGISTER e INVITE de assinantes são fail-closed: se a API não autorizar ou se o digest SIP falhar, a
requisição é negada. Chamadas locais usam `lookup("location")`; chamadas de saída usam o contrato
`/api/v1/softswitch/kamailio/route`.

Inbound por trunk/IP ainda não é habilitado automaticamente por este conector. Esse caminho precisa
de contrato explícito de trusted source e policy no API/control plane antes de aceitar chamadas sem
digest de assinante.

## Lifecycle

```bash
bash scripts/validate-kamailio-softswitch.sh
bash scripts/update-kamailio-softswitch.sh --ref v0.1.1
bash scripts/update-latest-kamailio-softswitch.sh stable
bash scripts/rollback-kamailio-softswitch.sh
```

## Troubleshooting

Comandos úteis:

```bash
kamailio -c -f /etc/kamailio/kamailio.cfg
systemctl status kamailio
journalctl -u kamailio -f
sngrep -d any port 5060
tcpdump -ni any udp port 5060
```

Para validar o endpoint:

```bash
NODE_UUID="$(tr -d '[:space:]' < /etc/mnscloud/softswitch/node.uuid)"
API_TOKEN="$(tr -d '[:space:]' < /etc/mnscloud/softswitch/api.token)"
API_BASE="$(tr -d '[:space:]' < /etc/mnscloud/softswitch/api.base)"
curl -sS -X POST "${API_BASE}/api/v1/softswitch/kamailio/heartbeat?node_uuid=${NODE_UUID}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  --data '{"hostname":"pabx-dev1"}'
```
