# Reverse Engineering Timestamp

## Run Record

- Date: 2026-11-03
- Commit: 5b2093db7c36855f7d5b59e1e29d3cb2580857e1

## Scope of Analysis

```yaml
scope_version: 1
kind: full
intent: discord-multi-server
fingerprint: 1adf138c4b29d32e14c6c190f2ca2baf0d0b9e7f
analyzed:
  paths:
    - ./
  components:
    - bootstrap
    - envs-prod
    - network
    - minecraft_server
    - host-scripts
    - world_backup
    - notifier
    - watchdog
    - monitoring
    - minecraft-container
    - ci-tooling
    - cd-tooling
    - local-tooling
    - client-guide
shallow:
  paths:
    - bootstrap/.terraform.lock.hcl
    - envs/prod/.terraform.lock.hcl
    - modules/minecraft_server/.terraform.lock.hcl
    - modules/monitoring/.terraform.lock.hcl
    - modules/network/.terraform.lock.hcl
    - modules/notifier/.terraform.lock.hcl
    - modules/watchdog/.terraform.lock.hcl
    - modules/world_backup/.terraform.lock.hcl
    - docs/images/
    - LICENSE
```
