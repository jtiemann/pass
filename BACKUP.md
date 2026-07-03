# Backup & recovery runbook

Pass protects your family's most important information — which means **losing the
database or the encryption key is the exact disaster this app exists to prevent**.
Read this once, set it up, and test it twice a year.

## The two things you must never lose

| What | Where it lives | If lost |
| ---- | -------------- | ------- |
| **The Postgres database** | your Postgres server / Docker volume | everything is gone |
| **`PASS_CLOAK_KEY`** | your environment / secret manager | credentials & documents become permanently unreadable, even with a perfect DB backup |

They are only useful **together**. Store them separately but durably.

## 1. Back up the database

Nightly (or after meaningful changes):

```bash
# Native Postgres
pg_dump -h localhost -U postgres -Fc pass_prod > pass-$(date +%F).dump

# Postgres in Docker
docker exec <container> pg_dump -U postgres -Fc pass_prod > pass-$(date +%F).dump
```

- `-Fc` (custom format) allows selective, compressed restores.
- Keep at least: 7 daily, 4 weekly, 12 monthly copies.
- Store at least one copy **off the machine** (external drive, another computer,
  or encrypted cloud storage). The dump contains ciphertext for secrets — it is
  safe-ish at rest, but treat it as sensitive anyway.

Restore:

```bash
createdb -h localhost -U postgres pass_prod
pg_restore -h localhost -U postgres -d pass_prod pass-2026-07-03.dump
```

## 2. Escrow the encryption key

`PASS_CLOAK_KEY` is a base64, 32-byte AES key. Without it, backups are noise.

- Print it (or write it by hand) and keep it in a **fire safe or bank deposit box**.
- Optionally give a sealed copy to your attorney or the family's most trusted member.
- If you ever rotate the key, re-escrow it immediately — old backups need the key
  that encrypted them.

Also escrow `SECRET_KEY_BASE`? No — it only signs cookies; a new one just logs
everyone out. Only `PASS_CLOAK_KEY` is unrecoverable.

## 3. The emergency kit (plaintext export)

For the scenario where nobody technical is available, keep a **printed** snapshot
of the vault with your key escrow:

```bash
mix pass.export > vault-export.json
```

This prints every asset, its access/ownership/sale instructions, **decrypted**
credentials, and contacts. Print it, store it with the key in the safe, shred old
copies when you refresh it. Never leave the file on disk or in email.

Document *files* (deeds, titles…) are not in the export — they're in the DB
backup — so also keep paper originals of anything truly critical.

## 4. Test your restore (twice a year)

A backup you've never restored is a hope, not a backup.

1. Restore the latest dump into a scratch database
   (`createdb pass_restore_test && pg_restore -d pass_restore_test …`).
2. Point a dev instance at it with the production `PASS_CLOAK_KEY`.
3. Log in, reveal one credential, download one document.
4. Drop the scratch DB.

If step 3 works, your family can recover. Put a reminder in your calendar.
