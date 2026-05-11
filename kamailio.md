# Kamailio Softswitch

Este diretório documenta o uso do Kamailio como camada Softswitch/SIP edge do mnscloud.

## Modelo

- O servidor físico mantém um UUID local em `/etc/mnscloud/softswitch/node.uuid`.
- Esse UUID é vinculado ao cadastro `VoipSoftswitchServer.VsrNodeUUID`.
- Cada requisição runtime enviada ao mnscloud usa `node_uuid` para validar o servidor.
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

O `node_uuid` pode ir via query string ou header `X-Softswitch-Node-UUID`. O bootstrap exige
`Authorization: Bearer <token>` usando `KAMAILIO_API_TOKEN` ou `SOFTSWITCH_API_TOKEN`.

## Instalação

Execute:

```bash
bash scripts/install-kamailio.sh
```

O instalador:

- configura o repositório oficial Kamailio 6.1.x antes da instalação;
  - Debian 12/13: `http://deb.kamailio.org/kamailio61` com keyring `/usr/share/keyrings/kamailio.gpg`;
  - Debian usa pinning em `/etc/apt/preferences.d/kamailio` para preferir os pacotes 6.1.x oficiais em vez dos pacotes antigos da distribuição;
  - Rocky 8/9: `https://rpm.kamailio.org/rocky/<major>/6.1/6.1/<arch>/`;
- instala Kamailio e ferramentas de troubleshooting (`sngrep`, `tcpdump`, `ngrep`, `mtr`, `jq`, etc.);
- cria ou reaproveita `/etc/mnscloud/softswitch/node.uuid`;
- tenta vincular o node UUID via API bootstrap usando hostname, IPv4 privado e IPv4 público descoberto;
- não executa SQL direto nem instala cliente MariaDB para vincular o node UUID;
- faz backup do `/etc/kamailio/kamailio.cfg` original como `.bkp`;
- gera um `kamailio.cfg` mínimo para consulta HTTP ao mnscloud.

O arquivo gerado usa `http_async_client` no padrão Kamailio 6.1: `http_async_query(url, route_name)`.
Quando houver corpo POST, o instalador configura `$http_req(method)`, `$http_req(hdr)` e `$http_req(body)` antes da chamada.
O `tm.so` é carregado antes dos módulos que dependem de transação, como `sl.so` e `http_async_client.so`.

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
curl -sS -X POST "https://dev1.publichost.cloud/api/v1/softswitch/kamailio/heartbeat?node_uuid=${NODE_UUID}" \
  -H "Content-Type: application/json" \
  --data '{"hostname":"pabx-dev1"}'
```
