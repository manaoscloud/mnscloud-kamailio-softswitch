# MNSCloud Kamailio

Public standalone Kamailio edge connector for MNSCloud.

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

- Product/runtime: `mnscloud-kamailio`
- Project directory: `/opt/mnscloud/mnscloud-kamailio`
- Installer: `scripts/install-kamailio.sh`
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
gh repo clone manaoscloud/mnscloud-kamailio
cd /opt/mnscloud/mnscloud-kamailio
sudo bash scripts/install-kamailio.sh
```

See `kamailio.md` and `SECURITY.md` for details.
