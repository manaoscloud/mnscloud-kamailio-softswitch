# MNSCloud Kamailio Softswitch

Public standalone Kamailio softswitch connector for MNSCloud.

This repository installs and configures local Kamailio runtime assets that consume the MNSCloud API
contract. It can run on MNSCloud, customer, or partner infrastructure.

## Boundary

- This repository is public and auditable by design.
- It must remain standalone and must not depend on the private MNSCloud monorepo at runtime.
- The MNSCloud API is the source of truth for authorization, tenant scope, routing ownership, billing,
  policy, and secret resolution.
- Do not commit secrets, customer data, production infrastructure values, provider credentials, or
  private business rules.
- This repository is the generic Kamailio softswitch/SIP connector. WebRTC SIP
  over WebSocket, local WebRTC TLS termination, and rtpengine media anchoring
  belong to `mnscloud-kamailio-webrtc`.

## Contract

- Product/runtime: `mnscloud-kamailio-softswitch`
- Project directory: `/opt/mnscloud/mnscloud-kamailio-softswitch`
- Installer: `scripts/install-kamailio-softswitch.sh`
- Validator: `scripts/validate-kamailio-softswitch.sh`
- Update by ref: `scripts/update-kamailio-softswitch.sh --ref <git-ref>`
- Update channel: `scripts/update-latest-kamailio-softswitch.sh [stable]`
- Rollback local Kamailio cfg: `scripts/rollback-kamailio-softswitch.sh`
- Shared package installer: `mnscloud-runtime-kit`
- Service: `kamailio.service`
- Local state prefix: `/etc/mnscloud/softswitch`
- Node UUID: `/etc/mnscloud/softswitch/node.uuid`
- API token: `/etc/mnscloud/softswitch/api.token`
- API base URL: `/etc/mnscloud/softswitch/api.base`
- Kamailio config: `/etc/kamailio/kamailio.cfg`
- Config validation: `kamailio -c -f /etc/kamailio/kamailio.cfg`

## Install

Install GitHub CLI if needed:
[cli/cli installation](https://github.com/cli/cli#installation).

Authenticate GitHub CLI:

```bash
gh auth login
```

Clone the private repository and install:

```bash
sudo install -d -m 0755 /opt/mnscloud
cd /opt/mnscloud
gh repo clone manaoscloud/mnscloud-kamailio-softswitch
cd /opt/mnscloud/mnscloud-kamailio-softswitch
sudo bash scripts/install-kamailio-softswitch.sh
```

See `kamailio.md` and `SECURITY.md` for details.

## Runtime Behavior

- SIP REGISTER is authorized by the MNSCloud runtime API and then validated with real SIP digest
  authentication before the contact is saved locally.
- SIP INVITE from subscribers is also proxy-authenticated before local lookup or outbound routing.
- Local subscriber-to-subscriber calls use Kamailio `usrloc` after authentication.
- Outbound calls use `/api/v1/softswitch/runtime/route`; the API remains responsible for tenant,
  policy, ownership, and route selection.
- Inbound trunk calls use `/api/v1/softswitch/runtime/route` with `direction=inbound`, source IP,
  and DID. The API only returns a route when the source IP matches the trunk `trustedCidrs` contract
  and the DID is active.
