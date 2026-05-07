# Kamailio Softswitch

Este diretório documenta o uso do Kamailio como camada Softswitch/SIP edge do Manaos Cloud.

## Modelo

- O servidor físico mantém um UUID local em `/etc/mnscloud/softswitch/node.uuid`.
- Esse UUID é vinculado ao cadastro `VoipSoftswitchServer.VsrNodeUUID`.
- Cada requisição runtime enviada ao Manaos Cloud usa `node_uuid` para validar o servidor.
- A API usa cache curto para a identidade do servidor, reduzindo IO por chamada sem perder revogação operacional.

## Cadastros

- `VoipSoftswitchProvider`: catálogo do provider/plataforma, com engines `kamailio`, `opensips`, `sippulse`, `vsc` e `custom`.
- `VoipSoftswitchServer`: servidores autorizados a consultar runtime.
- `VoipSoftswitchAccount`: vínculo tenant/domínio/customer/provider/server usado para autorizar domínios e assinantes.

## Endpoints Runtime

Os endpoints internos ficam em:

- `POST /api/v1/softswitch/kamailio/heartbeat`
- `POST /api/v1/softswitch/kamailio/auth`
- `POST /api/v1/softswitch/kamailio/route`
- `POST /api/v1/softswitch/kamailio/accounting`

O `node_uuid` pode ir via query string ou header `X-Softswitch-Node-UUID`.

## Instalação

Execute:

```bash
bash scripts/install-kamailio.sh
```

O instalador:

- instala Kamailio e ferramentas de troubleshooting (`sngrep`, `tcpdump`, `ngrep`, `mtr`, `jq`, etc.);
- cria ou reaproveita `/etc/mnscloud/softswitch/node.uuid`;
- tenta vincular o node UUID ao cadastro de servidor pelo hostname/IP quando as credenciais DB estão disponíveis;
- faz backup do `/etc/kamailio/kamailio.cfg` original como `.bkp`;
- gera um `kamailio.cfg` mínimo para consulta HTTP ao Manaos Cloud.

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
