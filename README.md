# Pass — a secure family asset vault

[![CI](https://github.com/jtiemann/pass/actions/workflows/ci.yml/badge.svg)](https://github.com/jtiemann/pass/actions/workflows/ci.yml)

**Pass** is a security-first web app for an individual or family to record their
assets and everything needed to **access, prove ownership of, or sell** them —
account logins, account numbers, paperwork (deeds, titles, statements), and the
people who can help (advisors, attorneys, agents).

- **Passkey (WebAuthn) two-factor login** on top of a password, with single-use recovery codes
- **Encryption at rest** (AES-GCM via Cloak) for credential secrets and uploaded documents
- **Shared family vault** with **roles** (owner / member / viewer), **email invites**,
  and an **audit log** of who accessed and changed what
- **Defense in depth**: rate-limited logins, re-authentication for security-sensitive
  settings, a strict Content-Security-Policy, and short (7-day) sessions
- **Backup story**: a [runbook](BACKUP.md) plus `mix pass.export` for a printable
  emergency kit
- Built with **Elixir / Phoenix LiveView**, with **Ramda** and **RxJS** in the browser
  (the reveal/copy flow auto-clears secrets and wipes the clipboard)

---

## Table of contents

- [Prerequisites](#prerequisites)
- [Install the prerequisites](#install-the-prerequisites)
  - [Linux](#linux)
  - [macOS](#macos)
  - [Windows](#windows)
- [Get the app running](#get-the-app-running)
- [Environment variables](#environment-variables)
- [First run](#first-run)
- [Running the tests](#running-the-tests)
- [Production notes](#production-notes)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Tool           | Version                     | Why                                             |
| -------------- | --------------------------- | ----------------------------------------------- |
| **Erlang/OTP** | 27                          | Runtime                                         |
| **Elixir**     | 1.17+ (built for OTP 27)    | Language — **must match your OTP**              |
| **Node.js**    | 18+                         | Bundles the JS deps (Ramda, RxJS)               |
| **PostgreSQL** | 14+ (17 recommended)        | Database                                        |

> **Important:** Elixir must be compiled against the **same OTP** you have installed.
> An Elixir built for OTP 25/26 will throw `beam_load` errors on OTP 27. When in doubt,
> install Elixir 1.18 for OTP 27.

---

## Install the prerequisites

### Linux

**Recommended: [asdf](https://asdf-vm.com) for Erlang + Elixir + Node** (keeps versions matched).

```bash
# Build deps for Erlang (Debian/Ubuntu)
sudo apt-get update
sudo apt-get install -y build-essential autoconf m4 libncurses5-dev \
  libssl-dev libwxgtk3.2-dev libgl1-mesa-dev libglu1-mesa-dev libpng-dev \
  libssh-dev unixodbc-dev xsltproc fop libxml2-utils

# asdf plugins
asdf plugin add erlang
asdf plugin add elixir
asdf plugin add nodejs

# Install matched versions
asdf install erlang 27.2
asdf install elixir 1.18.3-otp-27
asdf install nodejs 22.14.0
asdf global erlang 27.2
asdf global elixir 1.18.3-otp-27
asdf global nodejs 22.14.0
```

**PostgreSQL** — native or Docker:

```bash
# Native (Debian/Ubuntu)
sudo apt-get install -y postgresql
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"

# …or Docker
docker run --name pass-db -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:17
```

### macOS

**Recommended: [Homebrew](https://brew.sh) + asdf.**

```bash
brew install asdf autoconf openssl wxwidgets libxslt fop

asdf plugin add erlang
asdf plugin add elixir
asdf plugin add nodejs
asdf install erlang 27.2
asdf install elixir 1.18.3-otp-27
asdf install nodejs 22.14.0
asdf global erlang 27.2
asdf global elixir 1.18.3-otp-27
asdf global nodejs 22.14.0
```

Or, if you prefer Homebrew formulae directly: `brew install elixir node postgresql@17`
(note: Homebrew's `elixir` tracks the latest, which targets current OTP — fine).

**PostgreSQL:**

```bash
brew install postgresql@17
brew services start postgresql@17
# The default superuser is your macOS username with no password. Either create a
# `postgres` role, or set PASS_DB_PASSWORD/username to match (see Environment).
createuser -s postgres 2>/dev/null || true
```

### Windows

Use the official installers (simplest), or a package manager.

**Official installers**

- **Erlang/OTP 27** and **Elixir 1.18** — https://elixir-lang.org/install.html#windows
  (install Erlang first, then the Elixir installer for the matching OTP).
- **Node.js LTS** — https://nodejs.org
- **PostgreSQL 17** — https://www.postgresql.org/download/windows/ (remember the
  password you set for the `postgres` user).

**…or with [Chocolatey](https://chocolatey.org)** (run PowerShell as Administrator):

```powershell
choco install erlang elixir nodejs postgresql
```

**…or [Scoop](https://scoop.sh):**

```powershell
scoop install erlang elixir nodejs postgresql
```

> If you have **two Elixir installs** on your `PATH` (a common Windows situation),
> make sure the one built for **OTP 27** wins. Check with `elixir --version` — it
> should say `compiled with Erlang/OTP 27`.

Use **Git Bash** or **PowerShell** for the commands below.

---

## Get the app running

```bash
# 1. Clone
git clone https://github.com/jtiemann/pass.git
cd pass

# 2. Install the JavaScript deps (Ramda, RxJS) — REQUIRED before assets are built
npm install --prefix assets

# 3. Tell the app your Postgres password (see Environment variables).
#    Easiest: an untracked .env file at the project root —
echo "PASS_DB_PASSWORD=postgres" > .env
#    …or a shell variable:
#    Linux/macOS:              export PASS_DB_PASSWORD=postgres
#    Windows (PowerShell):     $env:PASS_DB_PASSWORD = "postgres"
#    Windows (persist):        setx PASS_DB_PASSWORD postgres   (reopen the terminal)

# 4. Fetch Elixir deps, create + migrate the DB, and build assets
mix setup

# 5. Start the server
mix phx.server
```

Now visit **http://localhost:4000**.

> **Step 2 is not optional.** The browser code imports Ramda and RxJS, so
> `mix setup` (which builds assets) will fail if `assets/node_modules` isn't present.
> Run `npm install --prefix assets` first.

To run inside an interactive shell: `iex -S mix phx.server`.

---

## Environment variables

### Development / test

| Variable           | Default      | Notes                                                  |
| ------------------ | ------------ | ------------------------------------------------------ |
| `PASS_DB_PASSWORD` | `postgres`   | Password for the local Postgres `postgres` user.       |
| `PASS_CLOAK_KEY`   | dev-only key | Base64 32-byte encryption key. A **dev-only** default is baked in for local use; override to use your own. |

In development, `PASS_DB_PASSWORD` can also live in an untracked **`.env`** file at
the project root (`PASS_DB_PASSWORD=yourpassword`) — handy for editors and tools
that launch the server without your shell profile. A real environment variable
takes precedence over `.env`.

The dev/test database user is `postgres` on `localhost:5432`. If your setup differs,
edit `config/dev.exs` / `config/test.exs`.

### Production (required — the app refuses to boot without these)

| Variable          | How to generate                                             |
| ----------------- | ----------------------------------------------------------- |
| `DATABASE_URL`    | `ecto://USER:PASS@HOST/DATABASE`                            |
| `SECRET_KEY_BASE` | `mix phx.gen.secret`                                        |
| `PASS_CLOAK_KEY`  | `elixir -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))'` |
| `PHX_HOST`        | your domain, e.g. `vault.example.com`                       |
| `PORT`            | e.g. `4000`                                                 |

> **Keep `PASS_CLOAK_KEY` safe and stable.** It decrypts your credentials and
> documents — if you lose it, that data is unrecoverable; if it changes, existing
> encrypted data can't be read.

---

## First run

1. Visit **http://localhost:4000** and click **Sign up**.
2. **The first account to register becomes the `owner`** (full access + member management).
   Subsequent sign-ups are `member`s; an owner can change roles under **Members**.
3. Check **http://localhost:4000/dev/mailbox** for the confirmation email (dev uses a
   local mailbox — no real mail is sent).
4. Set a password under **Settings**.
5. Under **Settings → Manage passkeys**, enroll a **passkey** (Touch ID / Windows Hello /
   a security key) and **generate recovery codes**. Once you have a passkey, every login
   requires it as the second factor.
6. Invite the rest of the family from **Members** (email + role) — each invitee gets a
   login link by email (in dev, it lands in `/dev/mailbox`).

> **Re-authentication prompts:** managing passkeys, recovery codes, and member roles
> requires a login fresher than 10 minutes. Being bounced to the login page there is
> the security model working, not a bug.

> **Passkeys and HTTPS:** WebAuthn requires a secure context. `localhost` is exempt, so
> passkeys work in development over HTTP. In production you **must** serve the app over
> **HTTPS**.

---

## Running the tests

```bash
# Uses the `pass_test` database; honors PASS_DB_PASSWORD too.
mix test
```

Handy checks:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
```

---

## Production notes

- **Set up backups before putting real data in.** See [BACKUP.md](BACKUP.md) —
  it covers database dumps, escrowing `PASS_CLOAK_KEY` (losing it makes encrypted
  data unrecoverable), and the printable emergency kit (`mix pass.export`).
- Serve over **HTTPS** (required for passkeys).
- Set all production environment variables (see [Environment variables](#environment-variables)).
- Build a release with assets:
  ```bash
  npm install --prefix assets
  MIX_ENV=prod mix assets.deploy
  MIX_ENV=prod mix release
  ```
- See the [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html).

---

## Troubleshooting

**`beam_load` / `op make_fun2` errors when running `mix`.**
Your Elixir was built for a different OTP than you have installed. Install an Elixir
built for **OTP 27** (e.g. 1.18.x) and make sure it's the one on your `PATH`
(`elixir --version` should say *compiled with Erlang/OTP 27*).

**`mix setup` fails building assets / "Could not resolve 'ramda'".**
You skipped `npm install --prefix assets`. Run it, then `mix assets.build`.

**Can't connect to the database.**
Make sure Postgres is running and `PASS_DB_PASSWORD` matches your `postgres` user's
password. Test with `psql -h localhost -U postgres`.

**Passkey prompt never appears / fails in the browser.**
Passkeys need a secure context. Use `http://localhost:4000` (exempt) in dev, or HTTPS
in production — not a LAN IP over plain HTTP.

**Windows: "empty assets are being served" warning.**
Phoenix can't create symlinks without privileges. Start your terminal **as
Administrator** once, then run the app.

**Windows: styles stop updating / new UI looks unstyled.**
The Tailwind CLI can intermittently die with an `EEXIST` error on Windows
(especially under synced folders like OneDrive), which silently kills the CSS
watcher. Rebuild manually and restart the server:

```bash
rm -rf priv/static/assets/css
mix tailwind pass
```
