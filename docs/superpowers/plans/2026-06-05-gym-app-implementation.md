# Gym App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully responsive gym management web application with class scheduling, personalized athlete programming, workout execution mode, and gamification — self-hosted on owner's servers using Elixir/Phoenix + Next.js.

**Architecture:** Hexagonal architecture (4 layers: Interface → Application → Domain → Infrastructure) with Phoenix Contexts as bounded contexts. Backend (Phoenix API) and Frontend (Next.js) are separate apps communicating via REST (TanStack Query) and WebSocket (Phoenix Channels). See §2 of the design doc for all non-negotiable architectural constraints.

**Tech Stack:** Elixir/Phoenix 1.7+, Next.js 15 (App Router), TypeScript, Tailwind CSS, PostgreSQL 16, Redis 7+, Meilisearch, MinIO, Oban, Guardian, Docker Compose, Caddy.

**Design Doc:** `docs/superpowers/specs/2026-06-05-gym-app-design.md` — READ THIS FIRST BEFORE EVERY PHASE.

---

## Commit Philosophy (apply throughout ALL phases)

Every commit must be:
- **Atomic:** one logical change only (a schema, a context function, a component — never mixed)
- **Semantic:** prefix with `feat:`, `fix:`, `test:`, `chore:`, `docs:`, `refactor:`
- **Dependency-ordered:** infrastructure before application, domain before interface, backend before frontend
- **Insightful:** message explains WHY, not WHAT (e.g., `feat: add booking timeout Oban job — auto-alert admin after X mins of no response` not `add job`)

```bash
# Pattern for every commit:
git add <specific files only — never git add .>
git commit -m "$(cat <<'EOF'
feat(scheduling): add BookingTimeoutJob — auto-alert admin after X mins

Oban job scheduled on booking creation. No-ops if already resolved.
Cancels itself on approval/rejection via Oban.cancel_job/1.
EOF
)"
```

---

## ADR Format (apply throughout ALL phases)

Save every ADR to `docs/adr/ADR-NNN-title.md`:

```markdown
# ADR-NNN: [Title]
Date: YYYY-MM-DD
Status: Accepted | Superseded by ADR-XXX

## Context
[Why this decision was needed]

## Decision
[What was decided]

## Rationale
[Why this option over alternatives]

## Alternatives Considered
[What else was evaluated and why rejected]

## Consequences
[Trade-offs, constraints introduced, follow-up work]

## Implementation Notes  ← filled in AFTER implementation
[Emergent decisions, deviations from plan, new constraints discovered]
```

---

## Technical Debt Ledger Format

`docs/technical_debt.md` — append a row per deferred item:

```markdown
| ID | Phase | Description | Reason deferred | Priority | Added |
|---|---|---|---|---|---|
| TD-001 | Phase 3 | Stripe payment integration | Manual-only in v1 | Medium | 2026-06-05 |
```

---

## Phase 0: Project Scaffold & Infrastructure

**Goal:** Working monorepo with Phoenix API + Next.js frontend running locally via Docker Compose, with ADR infrastructure, CI skeleton, and git initialized.

**Deliverable:** `docker compose up` starts all services. `curl http://localhost/api/health` returns `{"status":"ok"}`. `http://localhost` serves Next.js default page.

### File Map

```
milos/
├── apps/
│   ├── api/                          # Phoenix app (MilosTraining)
│   └── web/                          # Next.js app
├── docs/
│   ├── adr/
│   │   ├── README.md
│   │   └── template.md
│   ├── technical_debt.md
│   └── superpowers/
│       ├── specs/
│       └── plans/
├── docker-compose.yml
├── docker-compose.override.yml       # dev overrides (hot reload, ports)
├── Caddyfile
├── .gitignore
└── .github/
    └── workflows/
        └── ci.yml
```

### Checklist

- [ ] **Read:** `docs/superpowers/specs/2026-06-05-gym-app-design.md` §1, §2, §10 (Overview, Architecture Constraints, Tech Stack)

- [ ] **Write ADR-001:** Project scaffold decisions (monorepo structure, apps/api + apps/web split, Docker Compose over Kubernetes, Caddy over Nginx)

- [ ] **Initialize git**
  ```bash
  cd /home/rodochrousbisbiki/MyApps/milos
  git init
  git branch -M main
  ```

- [ ] **Create `.gitignore`**
  ```gitignore
  # Elixir
  apps/api/_build/
  apps/api/deps/
  apps/api/.elixir_ls/
  apps/api/priv/static/uploads/

  # Node
  apps/web/node_modules/
  apps/web/.next/
  apps/web/.env*.local

  # Docker
  .postgres-data/
  .redis-data/
  .meilisearch-data/
  .minio-data/

  # Superpowers
  .superpowers/

  # Env files
  .env
  .env.local
  *.secret
  ```

- [ ] **Scaffold Phoenix app**
  ```bash
  cd apps
  mix phx.new api --app milos_training --no-html --no-assets --no-live --database postgres
  cd api
  ```

- [ ] **Scaffold Next.js app**
  ```bash
  cd apps
  npx create-next-app@latest web \
    --typescript --tailwind --eslint \
    --app --src-dir --no-turbo \
    --import-alias "@/*"
  ```

- [ ] **Create `docker-compose.yml`**
  ```yaml
  version: "3.9"
  services:
    api:
      build: ./apps/api
      env_file: .env
      depends_on: [postgres, redis, meilisearch]
      networks: [app]

    web:
      build: ./apps/web
      env_file: .env
      networks: [app]

    caddy:
      image: caddy:2-alpine
      ports: ["80:80", "443:443"]
      volumes:
        - ./Caddyfile:/etc/caddy/Caddyfile
        - caddy_data:/data
        - caddy_config:/config
      depends_on: [api, web]
      networks: [app]

    postgres:
      image: postgres:16-alpine
      environment:
        POSTGRES_USER: ${DB_USER}
        POSTGRES_PASSWORD: ${DB_PASSWORD}
        POSTGRES_DB: milos_training_dev
      volumes: [.postgres-data:/var/lib/postgresql/data]
      networks: [app]

    redis:
      image: redis:7-alpine
      networks: [app]

    meilisearch:
      image: getmeili/meilisearch:latest
      environment:
        MEILI_MASTER_KEY: ${MEILI_MASTER_KEY}
      volumes: [.meilisearch-data:/meili_data]
      networks: [app]

    minio:
      image: minio/minio
      command: server /data --console-address ":9001"
      environment:
        MINIO_ROOT_USER: ${MINIO_ROOT_USER}
        MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
      volumes: [.minio-data:/data]
      networks: [app]

  volumes:
    caddy_data:
    caddy_config:

  networks:
    app:
  ```

- [ ] **Create `Caddyfile`**
  ```
  {
    email admin@example.com
  }

  localhost {
    reverse_proxy /api/* api:4000
    reverse_proxy web:3000
  }
  ```

- [ ] **Create `apps/api/Dockerfile`**
  ```dockerfile
  FROM elixir:1.17-otp-27-alpine AS build
  RUN apk add --no-cache build-base git
  WORKDIR /app
  COPY mix.exs mix.lock ./
  RUN mix local.hex --force && mix local.rebar --force
  ENV MIX_ENV=prod
  RUN mix deps.get --only prod
  COPY . .
  RUN mix compile && mix release

  FROM alpine:3.19 AS runtime
  RUN apk add --no-cache libstdc++ openssl ncurses-libs
  WORKDIR /app
  COPY --from=build /app/_build/prod/rel/milos_training ./
  CMD ["./bin/milos_training", "start"]
  ```

- [ ] **Create `apps/api/Dockerfile.dev`** (hot reload for development)
  ```dockerfile
  FROM elixir:1.17-otp-27-alpine
  RUN apk add --no-cache build-base git inotify-tools
  WORKDIR /app
  RUN mix local.hex --force && mix local.rebar --force
  CMD ["mix", "phx.server"]
  ```

- [ ] **Add Phoenix health endpoint**

  Create `apps/api/lib/milos_training_web/controllers/health_controller.ex`:
  ```elixir
  defmodule MilosTrainingWeb.HealthController do
    use MilosTrainingWeb, :controller

    def index(conn, _params) do
      json(conn, %{status: "ok", version: Application.spec(:milos_training, :vsn)})
    end
  end
  ```

  Add to `apps/api/lib/milos_training_web/router.ex`:
  ```elixir
  scope "/api" do
    get "/health", HealthController, :index
  end
  ```

- [ ] **Add `open_api_spex` to `apps/api/mix.exs`**
  ```elixir
  {:open_api_spex, "~> 3.18"},
  ```

- [ ] **Add `oban` to `apps/api/mix.exs`**
  ```elixir
  {:oban, "~> 2.17"},
  ```

- [ ] **Add `guardian` and `argon2_elixir` to `apps/api/mix.exs`**
  ```elixir
  {:guardian, "~> 2.3"},
  {:argon2_elixir, "~> 4.0"},
  ```

- [ ] **Add `redix` to `apps/api/mix.exs`**
  ```elixir
  {:redix, "~> 1.3"},
  ```

- [ ] **Configure Oban in `apps/api/config/config.exs`**
  ```elixir
  config :milos_training, Oban,
    repo: MilosTraining.Repo,
    queues: [
      default: 10,
      notifications: 20,
      gamification: 5,
      analytics: 3
    ]
  ```

- [ ] **Initialize ADR directory**
  ```bash
  mkdir -p docs/adr
  ```

  Create `docs/adr/README.md`:
  ```markdown
  # Architecture Decision Records

  ADRs document significant architectural decisions for this project.
  Every non-trivial decision — especially those that constrain future work —
  must have an ADR. See `template.md` for the format.

  | ADR | Title | Status |
  |---|---|---|
  | ADR-001 | Project scaffold and monorepo structure | Accepted |
  ```

  Create `docs/adr/template.md` with the ADR format from above.

- [ ] **Initialize Technical Debt Ledger**

  Create `docs/technical_debt.md`:
  ```markdown
  # Technical Debt Ledger

  | ID | Phase | Description | Reason deferred | Priority | Added |
  |---|---|---|---|---|---|
  | TD-001 | Phase 0 | Stripe payment gateway integration | Manual-only in v1 per spec | Medium | 2026-06-05 |
  ```

- [ ] **Create GitHub Actions CI skeleton**

  Create `.github/workflows/ci.yml`:
  ```yaml
  name: CI
  on: [push, pull_request]
  jobs:
    api-test:
      runs-on: self-hosted
      services:
        postgres:
          image: postgres:16-alpine
          env:
            POSTGRES_PASSWORD: postgres
          options: --health-cmd pg_isready
      steps:
        - uses: actions/checkout@v4
        - uses: erlef/setup-beam@v1
          with:
            elixir-version: "1.17"
            otp-version: "27"
        - run: mix deps.get
          working-directory: apps/api
        - run: mix test
          working-directory: apps/api
          env:
            DATABASE_URL: postgres://postgres:postgres@localhost/milos_training_test

    web-test:
      runs-on: self-hosted
      steps:
        - uses: actions/checkout@v4
        - uses: actions/setup-node@v4
          with: { node-version: "20" }
        - run: npm ci
          working-directory: apps/web
        - run: npm run build
          working-directory: apps/web
  ```

- [ ] **Write ADR-001** — save to `docs/adr/ADR-001-project-scaffold.md`

  Fill in:
  - **Context:** New project, choosing between monolith/umbrella/monorepo layouts and Docker Compose vs k8s
  - **Decision:** `apps/api` (Phoenix) + `apps/web` (Next.js) in one repo, Docker Compose for all services, Caddy for reverse proxy + TLS
  - **Rationale:** Medium scale (100–500 users) does not justify Kubernetes overhead; Caddy auto-TLS eliminates cert management; monorepo enables shared docs and coordinated CI
  - **Alternatives Considered:** Umbrella app (tighter coupling than desired), separate repos (harder CI coordination), Nginx (manual cert renewal), Traefik (more config overhead than Caddy)
  - **Consequences:** Single deployment unit, Docker Compose must be kept in sync as services evolve

- [ ] **LIVE TEST:** Run `docker compose up` and verify:
  - `curl http://localhost/api/health` → `{"status":"ok"}`
  - `http://localhost` serves Next.js
  - All containers healthy: `docker compose ps`

- [ ] **Update ADR-001** `Implementation Notes` with any deviations

- [ ] **Update `docs/technical_debt.md`** if any scaffold decisions were deferred

- [ ] **Commit & push** (in this order):
  ```
  chore: initialize git repo and add .gitignore
  chore: scaffold Phoenix API app (milos_training, no HTML)
  chore: scaffold Next.js frontend app (App Router, TypeScript, Tailwind)
  chore: add docker-compose.yml with all services (postgres, redis, meilisearch, minio, caddy)
  chore: add Dockerfiles for api (prod + dev) and web
  chore: add Phoenix health endpoint GET /api/health
  chore: add open_api_spex, oban, guardian, argon2_elixir, redix dependencies
  docs: initialize ADR directory with README and template
  docs: initialize technical debt ledger
  chore: add GitHub Actions CI skeleton (self-hosted runner)
  ```

---

## Phase 1: Identity & Authentication

**Goal:** Users can register (choosing member/athlete role), log in, receive JWT tokens, and be authorized by role on all API endpoints.

**Deliverable:** `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/refresh`. Protected endpoints return 401 without valid JWT. Admin can change a user's role.

### File Map

```
apps/api/lib/milos_training/
├── identity/
│   ├── user.ex                    # Ecto schema
│   ├── commands/
│   │   ├── register_user.ex       # Domain: changeset + validation
│   │   └── update_role.ex
│   ├── queries/
│   │   └── find_user.ex
│   └── identity.ex                # Context public API
├── infrastructure/
│   └── auth/
│       ├── guardian.ex            # Guardian implementation
│       ├── guardian_pipeline.ex   # Plug pipeline
│       └── password.ex            # Argon2 wrapper
└── application/
    └── register_user.ex           # Application Service

apps/api/lib/milos_training_web/
├── controllers/
│   └── auth_controller.ex
└── router.ex

apps/api/priv/repo/migrations/
└── YYYYMMDDHHMMSS_create_users.exs

apps/api/test/
├── milos_training/identity/
│   ├── register_user_test.exs
│   └── find_user_test.exs
└── milos_training_web/controllers/
    └── auth_controller_test.exs
```

### Checklist

- [ ] **Read:** Design doc §3 (User Roles), §4 (Flow 8 — Registration), §2.1–2.6 (Architecture Constraints)

- [ ] **Write ADR-002:** Authentication strategy (Guardian JWT + Argon2 over session-based auth; short-lived access token + refresh rotation)

- [ ] **Write failing test for user registration**

  `apps/api/test/milos_training/identity/register_user_test.exs`:
  ```elixir
  defmodule MilosTraining.Identity.RegisterUserTest do
    use MilosTraining.DataCase, async: true

    alias MilosTraining.Identity.Commands.RegisterUser

    describe "call/1" do
      test "creates user with valid params" do
        params = %{nickname: "atlas", password: "S3cur3P@ss!", role: :member}
        assert {:ok, user} = RegisterUser.call(params)
        assert user.nickname == "atlas"
        assert user.role == :member
        refute user.password_hash == "S3cur3P@ss!"
      end

      test "rejects duplicate nickname" do
        params = %{nickname: "atlas", password: "S3cur3P@ss!", role: :member}
        {:ok, _} = RegisterUser.call(params)
        assert {:error, changeset} = RegisterUser.call(params)
        assert "has already been taken" in errors_on(changeset).nickname
      end

      test "rejects invalid role" do
        params = %{nickname: "atlas", password: "S3cur3P@ss!", role: :admin}
        assert {:error, changeset} = RegisterUser.call(params)
        assert "is invalid" in errors_on(changeset).role
      end

      test "rejects weak password" do
        params = %{nickname: "atlas", password: "123", role: :member}
        assert {:error, changeset} = RegisterUser.call(params)
        assert errors_on(changeset).password != []
      end
    end
  end
  ```

- [ ] **Run test — verify it fails**
  ```bash
  cd apps/api && mix test test/milos_training/identity/register_user_test.exs
  # Expected: compile error or test failures
  ```

- [ ] **Create migration for users table**

  `apps/api/priv/repo/migrations/YYYYMMDDHHMMSS_create_users.exs`:
  ```elixir
  defmodule MilosTraining.Repo.Migrations.CreateUsers do
    use Ecto.Migration

    def change do
      create table(:users, primary_key: false) do
        add :id, :binary_id, primary_key: true
        add :nickname, :string, null: false
        add :password_hash, :string, null: false
        add :role, :string, null: false, default: "member"
        add :leaderboard_opt_in, :boolean, null: false, default: false
        timestamps()
      end

      create unique_index(:users, [:nickname])
      create index(:users, [:role])
    end
  end
  ```

- [ ] **Create User schema**

  `apps/api/lib/milos_training/identity/user.ex`:
  ```elixir
  defmodule MilosTraining.Identity.User do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @roles [:member, :athlete, :admin]

    schema "users" do
      field :nickname, :string
      field :password, :string, virtual: true
      field :password_hash, :string
      field :role, Ecto.Enum, values: @roles
      field :leaderboard_opt_in, :boolean, default: false
      timestamps()
    end

    def registration_changeset(user \\ %__MODULE__{}, params) do
      user
      |> cast(params, [:nickname, :password, :role])
      |> validate_required([:nickname, :password, :role])
      |> validate_length(:nickname, min: 3, max: 30)
      |> validate_format(:nickname, ~r/^[a-zA-Z0-9_]+$/)
      |> validate_inclusion(:role, [:member, :athlete])  # admin cannot self-register
      |> validate_length(:password, min: 8)
      |> unique_constraint(:nickname)
      |> hash_password()
    end

    def role_changeset(user, params) do
      user
      |> cast(params, [:role])
      |> validate_required([:role])
      |> validate_inclusion(:role, @roles)
    end

    defp hash_password(%{valid?: false} = changeset), do: changeset
    defp hash_password(changeset) do
      password = get_change(changeset, :password)
      put_change(changeset, :password_hash, Argon2.hash_pwd_salt(password))
    end
  end
  ```

- [ ] **Create RegisterUser command**

  `apps/api/lib/milos_training/identity/commands/register_user.ex`:
  ```elixir
  defmodule MilosTraining.Identity.Commands.RegisterUser do
    alias MilosTraining.{Repo, Identity.User}

    def call(params) do
      %User{}
      |> User.registration_changeset(params)
      |> Repo.insert()
    end
  end
  ```

- [ ] **Create FindUser queries**

  `apps/api/lib/milos_training/identity/queries/find_user.ex`:
  ```elixir
  defmodule MilosTraining.Identity.Queries.FindUser do
    import Ecto.Query
    alias MilosTraining.{Repo, Identity.User}

    def by_nickname(nickname) do
      Repo.get_by(User, nickname: nickname)
    end

    def by_id(id) do
      Repo.get(User, id)
    end
  end
  ```

- [ ] **Create Identity context public API**

  `apps/api/lib/milos_training/identity/identity.ex`:
  ```elixir
  defmodule MilosTraining.Identity do
    alias MilosTraining.Identity.Commands.{RegisterUser, UpdateRole}
    alias MilosTraining.Identity.Queries.FindUser

    defdelegate register(params), to: RegisterUser, as: :call
    defdelegate find_by_nickname(nickname), to: FindUser, as: :by_nickname
    defdelegate find_by_id(id), to: FindUser, as: :by_id
    defdelegate update_role(user, role), to: UpdateRole, as: :call
  end
  ```

- [ ] **Run registration tests — verify they pass**
  ```bash
  cd apps/api && mix test test/milos_training/identity/register_user_test.exs
  # Expected: all green
  ```

- [ ] **Create Guardian implementation**

  `apps/api/lib/milos_training/infrastructure/auth/guardian.ex`:
  ```elixir
  defmodule MilosTraining.Auth.Guardian do
    use Guardian, otp_app: :milos_training
    alias MilosTraining.Identity

    def subject_for_token(user, _claims), do: {:ok, to_string(user.id)}

    def resource_from_claims(%{"sub" => id}) do
      case Identity.find_by_id(id) do
        nil -> {:error, :not_found}
        user -> {:ok, user}
      end
    end
  end
  ```

  Configure in `config/config.exs`:
  ```elixir
  config :milos_training, MilosTraining.Auth.Guardian,
    issuer: "milos_training",
    secret_key: {MilosTraining.Auth.Guardian, :fetch_secret, []},
    token_ttl: %{"access" => {15, :minutes}, "refresh" => {30, :days}}
  ```

- [ ] **Create auth controller**

  `apps/api/lib/milos_training_web/controllers/auth_controller.ex`:
  ```elixir
  defmodule MilosTrainingWeb.AuthController do
    use MilosTrainingWeb, :controller
    alias MilosTraining.{Identity, Auth.Guardian}

    def register(conn, params) do
      case Identity.register(params) do
        {:ok, user} ->
          {:ok, access, _} = Guardian.encode_and_sign(user, %{}, token_type: "access")
          {:ok, refresh, _} = Guardian.encode_and_sign(user, %{}, token_type: "refresh")
          conn |> put_status(:created) |> json(%{access_token: access, refresh_token: refresh})
        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end

    def login(conn, %{"nickname" => nickname, "password" => password}) do
      with user when not is_nil(user) <- Identity.find_by_nickname(nickname),
           true <- Argon2.verify_pass(password, user.password_hash),
           {:ok, access, _} <- Guardian.encode_and_sign(user, %{}, token_type: "access"),
           {:ok, refresh, _} <- Guardian.encode_and_sign(user, %{}, token_type: "refresh") do
        json(conn, %{access_token: access, refresh_token: refresh})
      else
        _ -> conn |> put_status(:unauthorized) |> json(%{error: "Invalid credentials"})
      end
    end

    def refresh(conn, %{"refresh_token" => token}) do
      case Guardian.exchange(token, "refresh", "access") do
        {:ok, _old, {new_access, _}} ->
          json(conn, %{access_token: new_access})
        {:error, _reason} ->
          conn |> put_status(:unauthorized) |> json(%{error: "Invalid refresh token"})
      end
    end

    defp format_errors(changeset) do
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)
    end
  end
  ```

- [ ] **Update router with auth routes and role-based pipelines**

  `apps/api/lib/milos_training_web/router.ex`:
  ```elixir
  defmodule MilosTrainingWeb.Router do
    use MilosTrainingWeb, :router

    pipeline :api do
      plug :accepts, ["json"]
    end

    pipeline :authenticated do
      plug Guardian.Plug.Pipeline, module: MilosTraining.Auth.Guardian,
        error_handler: MilosTrainingWeb.AuthErrorHandler
      plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
      plug Guardian.Plug.EnsureAuthenticated
      plug Guardian.Plug.LoadResource
    end

    pipeline :admin_only do
      plug MilosTrainingWeb.Plugs.RequireRole, role: :admin
    end

    pipeline :member_or_admin do
      plug MilosTrainingWeb.Plugs.RequireRole, roles: [:member, :admin]
    end

    pipeline :athlete_or_admin do
      plug MilosTrainingWeb.Plugs.RequireRole, roles: [:athlete, :admin]
    end

    scope "/api" do
      pipe_through :api
      get "/health", HealthController, :index
      post "/auth/register", AuthController, :register
      post "/auth/login", AuthController, :login
      post "/auth/refresh", AuthController, :refresh
    end
  end
  ```

- [ ] **Create RequireRole plug**

  `apps/api/lib/milos_training_web/plugs/require_role.ex`:
  ```elixir
  defmodule MilosTrainingWeb.Plugs.RequireRole do
    import Plug.Conn
    import Phoenix.Controller, only: [json: 2]

    def init(opts), do: opts

    def call(conn, opts) do
      user = Guardian.Plug.current_resource(conn)
      allowed = List.wrap(opts[:role] || opts[:roles])

      if user.role in allowed do
        conn
      else
        conn |> put_status(:forbidden) |> json(%{error: "Forbidden"}) |> halt()
      end
    end
  end
  ```

- [ ] **Write and run controller integration tests**

  `apps/api/test/milos_training_web/controllers/auth_controller_test.exs`:
  ```elixir
  defmodule MilosTrainingWeb.AuthControllerTest do
    use MilosTrainingWeb.ConnCase, async: true

    describe "POST /api/auth/register" do
      test "returns tokens on valid registration", %{conn: conn} do
        params = %{nickname: "zeus", password: "S3cur3P@ss!", role: "member"}
        conn = post(conn, "/api/auth/register", params)
        assert %{"access_token" => _, "refresh_token" => _} = json_response(conn, 201)
      end

      test "returns 422 on duplicate nickname", %{conn: conn} do
        params = %{nickname: "zeus", password: "S3cur3P@ss!", role: "member"}
        post(conn, "/api/auth/register", params)
        conn2 = post(conn, "/api/auth/register", params)
        assert json_response(conn2, 422)["errors"]["nickname"] != []
      end
    end

    describe "POST /api/auth/login" do
      setup do
        {:ok, _} = MilosTraining.Identity.register(%{
          nickname: "hermes", password: "S3cur3P@ss!", role: :member
        })
        :ok
      end

      test "returns tokens on valid credentials", %{conn: conn} do
        conn = post(conn, "/api/auth/login", %{nickname: "hermes", password: "S3cur3P@ss!"})
        assert json_response(conn, 200)["access_token"]
      end

      test "returns 401 on wrong password", %{conn: conn} do
        conn = post(conn, "/api/auth/login", %{nickname: "hermes", password: "wrong"})
        assert json_response(conn, 401)
      end
    end
  end
  ```

  ```bash
  cd apps/api && mix test test/milos_training_web/controllers/auth_controller_test.exs
  # Expected: all green
  ```

- [ ] **Add rate limiting for auth endpoints** via Redis

  Add to `apps/api/mix.exs`: `{:ex_rated, "~> 2.1"}`

  Add plug to auth routes: `plug MilosTrainingWeb.Plugs.RateLimit, max: 10, interval: 60_000`

- [ ] **Generate OpenAPI spec for auth endpoints** using `open_api_spex`

  Create `apps/api/lib/milos_training_web/api_spec.ex` with spec metadata. Add `@doc` and `@spec` to auth controller actions per `open_api_spex` conventions.

- [ ] **Generate TypeScript auth client**
  ```bash
  cd apps/web
  npx openapi-typescript http://localhost:4000/api/openapi --output src/api/generated/schema.ts
  ```

- [ ] **LIVE TEST:**
  - `docker compose up`
  - `curl -X POST http://localhost/api/auth/register -H "Content-Type: application/json" -d '{"nickname":"testuser","password":"S3cur3P@ss!","role":"member"}'` → returns `access_token`
  - `curl -X POST http://localhost/api/auth/login -d '{"nickname":"testuser","password":"S3cur3P@ss!"}'` → returns tokens
  - `curl -X POST http://localhost/api/auth/login -d '{"nickname":"testuser","password":"wrong"}'` → 401
  - Hit auth endpoint 11x rapidly → 429 rate limit response

- [ ] **Update ADR-002** `Implementation Notes`

- [ ] **Update `docs/technical_debt.md`** if any auth features deferred

- [ ] **Commit & push:**
  ```
  chore: add users migration (uuid pk, nickname unique, role enum)
  feat(identity): add User schema with registration and role changesets
  feat(identity): add RegisterUser command and FindUser queries
  feat(identity): add Identity context public API (register, find_by_*)
  feat(auth): add Guardian implementation with access + refresh tokens
  feat(auth): add RequireRole plug for role-based authorization
  feat(auth): add AuthController (register, login, refresh)
  feat(router): add auth routes and role pipelines (admin, member, athlete)
  feat(auth): add Redis-backed rate limiting on auth endpoints
  test(identity): add RegisterUser unit tests
  test(auth): add AuthController integration tests
  docs(openapi): add auth endpoints spec
  chore(web): generate TypeScript auth client from OpenAPI spec
  ```

---

## Phase 2: Workout Data Model & Content Management

**Goal:** Admin can create master workouts with sections, exercises, scale variations, and timer configs. The materialization engine produces correct scale instances at query time.

**Deliverable:** `POST /api/admin/workouts` creates a workout. `GET /api/workouts/:id/scales` returns materialized scale instances. Admin UI at `/admin/workouts` (workout creation form: Option A — linear with inline variations).

### File Map

```
apps/api/lib/milos_training/
├── workouts/
│   ├── master_workout.ex
│   ├── workout_section.ex
│   ├── workout_exercise.ex
│   ├── exercise_variation.ex
│   ├── domain/
│   │   └── workout_materializer.ex      # Pure Domain — no Repo
│   ├── commands/
│   │   ├── create_workout.ex
│   │   ├── update_workout.ex
│   │   └── delete_workout.ex
│   ├── queries/
│   │   ├── get_workout.ex
│   │   ├── get_week_view.ex
│   │   └── materialize_workout.ex
│   └── workouts.ex                      # Context public API
└── application/
    └── create_workout_with_sections.ex  # Orchestrates multi-step creation

apps/api/priv/repo/migrations/
├── ..._create_master_workouts.exs
├── ..._create_workout_sections.exs
├── ..._create_workout_exercises.exs
└── ..._create_exercise_variations.exs

apps/web/src/
├── app/admin/workouts/
│   ├── page.tsx                         # Workout list
│   └── new/
│       └── page.tsx                     # Workout creation form
├── components/workouts/
│   ├── WorkoutForm.tsx                  # Linear form (Option A)
│   ├── SectionEditor.tsx
│   ├── ExerciseEditor.tsx
│   └── VariationEditor.tsx
```

### Checklist

- [ ] **Read:** Design doc §4 (Flow 4), §5 (Data Models — Workout System), §2.1–2.4 (Architecture Constraints — especially Domain purity rule)

- [ ] **Write ADR-003:** Workout materialization strategy (query-time derivation via variation inheritance vs pre-materialized table — chose query-time for single source of truth)

- [ ] **Write failing test for WorkoutMaterializer domain module** (pure function — no DB)

  `apps/api/test/milos_training/workouts/domain/workout_materializer_test.exs`:
  ```elixir
  defmodule MilosTraining.Workouts.Domain.WorkoutMaterializerTest do
    use ExUnit.Case, async: true

    alias MilosTraining.Workouts.Domain.WorkoutMaterializer

    @base_workout %{
      id: "wod-a",
      sections: [
        %{
          id: "s1",
          exercises: [
            %{
              id: "e1", name: "Push-ups", base_reps: 10,
              variations: [
                %{scale_level: :beginner, reps: 8, description: "Knee push-ups"},
                %{scale_level: :intermediate, reps: 10, description: nil}
              ]
            },
            %{
              id: "e2", name: "Pull-ups", base_reps: 5,
              variations: [
                %{scale_level: :beginner, reps: 3, description: "Ring rows"},
                %{scale_level: :advanced, reps: 8, description: "Weighted"}
              ]
            }
          ]
        }
      ]
    }

    test "returns all scale levels that appear in at least one variation" do
      scales = WorkoutMaterializer.available_scales(@base_workout)
      assert Enum.sort(scales) == [:advanced, :beginner, :intermediate]
    end

    test "beginner instance overrides all beginner variations" do
      instance = WorkoutMaterializer.materialize(@base_workout, :beginner)
      e1 = get_exercise(instance, "e1")
      e2 = get_exercise(instance, "e2")
      assert e1.reps == 8
      assert e2.reps == 3
    end

    test "intermediate instance overrides only intermediate variations, base for rest" do
      instance = WorkoutMaterializer.materialize(@base_workout, :intermediate)
      e1 = get_exercise(instance, "e1")
      e2 = get_exercise(instance, "e2")
      assert e1.reps == 10   # intermediate variation
      assert e2.reps == 5    # base (no intermediate variation)
    end

    test "advanced instance overrides only advanced variations" do
      instance = WorkoutMaterializer.materialize(@base_workout, :advanced)
      e1 = get_exercise(instance, "e1")
      e2 = get_exercise(instance, "e2")
      assert e1.reps == 10   # base (no advanced variation for e1)
      assert e2.reps == 8    # advanced variation
    end

    defp get_exercise(instance, exercise_id) do
      instance.sections
      |> Enum.flat_map(& &1.exercises)
      |> Enum.find(&(&1.id == exercise_id))
    end
  end
  ```

- [ ] **Run test — verify it fails**
  ```bash
  cd apps/api && mix test test/milos_training/workouts/domain/workout_materializer_test.exs
  ```

- [ ] **Implement WorkoutMaterializer (pure Domain — no Repo, no Phoenix)**

  `apps/api/lib/milos_training/workouts/domain/workout_materializer.ex`:
  ```elixir
  defmodule MilosTraining.Workouts.Domain.WorkoutMaterializer do
    @moduledoc """
    Pure domain module. Derives scale-specific workout instances from a master
    workout by applying variation inheritance: each scale instance is the base
    workout with only its scale's variations applied.

    No Ecto, no Repo, no side effects.
    """

    @doc "Returns all scale levels that appear in at least one exercise variation."
    def available_scales(workout) do
      workout.sections
      |> Enum.flat_map(& &1.exercises)
      |> Enum.flat_map(& &1.variations)
      |> Enum.map(& &1.scale_level)
      |> Enum.uniq()
    end

    @doc """
    Produces a scale instance of the workout: a copy of the base workout where
    each exercise is overridden by its scale-specific variation (if one exists).
    """
    def materialize(workout, scale_level) do
      sections = Enum.map(workout.sections, fn section ->
        exercises = Enum.map(section.exercises, &apply_variation(&1, scale_level))
        %{section | exercises: exercises}
      end)

      %{workout | scale_level: scale_level, sections: sections}
    end

    defp apply_variation(exercise, scale_level) do
      case Enum.find(exercise.variations, &(&1.scale_level == scale_level)) do
        nil -> exercise
        variation ->
          exercise
          |> maybe_put(:reps, variation.reps)
          |> maybe_put(:sets, variation.sets)
          |> maybe_put(:duration_seconds, variation.duration_seconds)
          |> maybe_put(:description, variation.description)
      end
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)
  end
  ```

- [ ] **Run materializer tests — verify all pass**
  ```bash
  cd apps/api && mix test test/milos_training/workouts/domain/workout_materializer_test.exs
  # Expected: all green
  ```

- [ ] **Create migrations** for master_workouts, workout_sections (self-referential), workout_exercises, exercise_variations

  Key migration for `workout_sections`:
  ```elixir
  create table(:workout_sections, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :master_workout_id, references(:master_workouts, type: :binary_id, on_delete: :delete_all), null: false
    add :parent_section_id, references(:workout_sections, type: :binary_id), null: true
    add :name, :string, null: false
    add :order, :integer, null: false
    add :scoreable, :boolean, default: false, null: false
    add :score_config, :map       # jsonb
    add :timer_config, :map       # jsonb
    timestamps()
  end
  create index(:workout_sections, [:master_workout_id])
  create index(:workout_sections, [:parent_section_id])
  ```

- [ ] **Create Ecto schemas** for all four workout entities

- [ ] **Create CreateWorkout command + Workouts context public API**

- [ ] **Create MaterializeWorkout query** (loads workout from DB → feeds into `WorkoutMaterializer.materialize/2`)

- [ ] **Write and run full test suite** for workout creation + materialization with DB

  ```bash
  cd apps/api && mix test test/milos_training/workouts/
  ```

- [ ] **Create OpenAPI spec** for `POST /api/admin/workouts`, `GET /api/workouts/:id`, `GET /api/workouts/:id/scales`

- [ ] **Generate updated TypeScript client**

- [ ] **Build Admin workout creation UI** (`/admin/workouts/new`) — Option A linear form:
  - Section accordion with `+Add Section` button
  - Exercise rows with `+Variations` expandable panel
  - Timer config selector per section (type dropdown + dynamic fields)
  - "Preview Instances" tab group before save

- [ ] **LIVE TEST:**
  - Log in as admin
  - Create a workout with 2 exercises, variations for beginner/intermediate on exercise 1, advanced on exercise 2
  - `GET /api/workouts/:id/scales` → verify 3 instances returned with correct variation inheritance
  - Open `/admin/workouts` → new workout visible in list

- [ ] **Update ADR-003** `Implementation Notes`

- [ ] **Update `docs/technical_debt.md`** if needed

- [ ] **Commit & push** (ordered: migrations → schemas → domain → commands → queries → context → API → frontend)

---

## Phase 3: Class Scheduling & Booking

**Goal:** Admin can create/edit/delete time slots. Members can view the calendar filtered by type, preview workouts, and book slots. Bookings go through approval flow with Oban-driven timeout alerts.

**Deliverable:** Full `/schedule` page working end-to-end. Push notifications dispatched on booking events (stubs OK in this phase — full push in Phase 6).

### File Map

```
apps/api/lib/milos_training/
├── scheduling/
│   ├── scheduled_class.ex
│   ├── booking.ex
│   ├── domain/
│   │   └── booking_policy.ex           # Pure: can_book?, slot_full?, etc.
│   ├── commands/
│   │   ├── create_slot.ex
│   │   ├── update_slot.ex
│   │   ├── delete_slot.ex
│   │   ├── submit_booking.ex
│   │   ├── approve_booking.ex
│   │   └── reject_booking.ex
│   ├── queries/
│   │   ├── get_calendar_week.ex
│   │   └── get_pending_bookings.ex
│   └── scheduling.ex
├── infrastructure/
│   └── workers/
│       └── booking_timeout_job.ex      # Oban worker
└── application/
    ├── submit_booking.ex               # Orchestrates: create + schedule timeout + notify
    └── resolve_booking.ex             # Orchestrates: approve/reject + cancel job + notify

apps/web/src/
├── app/schedule/
│   └── page.tsx
├── components/schedule/
│   ├── CalendarView.tsx               # react-big-calendar wrapper
│   ├── TypeFilterChips.tsx
│   ├── SlotPopup.tsx                  # Workout preview popup
│   └── BookingModal.tsx
```

### Checklist

- [ ] **Read:** Design doc §4 (Flows 1, 5, 6), §5 (scheduled_classes, bookings), §2.4 (Application Services), §2.7 (Oban Job Chaining)

- [ ] **Write ADR-004:** Booking approval flow (Oban timeout job vs cron polling — chose Oban for reliability and no polling)

- [ ] **Write failing tests for BookingPolicy domain module**

- [ ] **Implement BookingPolicy, scheduled_class schema, booking schema, migrations**

- [ ] **Write failing tests for BookingTimeoutJob**

- [ ] **Implement BookingTimeoutJob**

- [ ] **Implement SubmitBooking Application Service**

  `apps/api/lib/milos_training/application/submit_booking.ex`:
  ```elixir
  defmodule MilosTraining.Application.SubmitBooking do
    alias MilosTraining.{Scheduling, Notifications}
    alias MilosTraining.Workers.BookingTimeoutJob

    def call(user_id, slot_id) do
      with {:ok, slot} <- Scheduling.get_slot(slot_id),
           :ok <- Scheduling.Domain.BookingPolicy.can_book?(slot, user_id: user_id),
           {:ok, booking} <- Scheduling.Commands.SubmitBooking.call(user_id, slot_id) do
        if slot.auto_approve do
          MilosTraining.Application.ResolveBooking.approve(booking.id, nil)
        else
          schedule_timeout(booking, slot)
          Notifications.notify_admin_new_booking(booking)
          {:ok, booking}
        end
      end
    end

    defp schedule_timeout(booking, slot) do
      scheduled_at = DateTime.add(booking.inserted_at, slot.booking_timeout_minutes * 60)
      BookingTimeoutJob.new(%{"booking_id" => booking.id}, scheduled_at: scheduled_at)
      |> Oban.insert()
    end
  end
  ```

- [ ] **Implement ResolveBooking Application Service** (approve/reject: cancel Oban job + notify member)

- [ ] **Create calendar API endpoints** (`GET /api/schedule`, `POST /api/bookings`, `PATCH /api/bookings/:id/approve`, `PATCH /api/bookings/:id/reject`)

- [ ] **Build `/schedule` frontend page** using `react-big-calendar`:
  - `TypeFilterChips` — filter state in Zustand
  - Calendar views: week (default desktop), 3-day (default mobile)
  - Slot click → `SlotPopup` with workout sections preview
  - "Book" button → `BookingModal` → POST to API
  - Admin view: `+` button per cell (add slot), right-click slot → edit/delete

- [ ] **Run full test suite for Phase 3**
  ```bash
  cd apps/api && mix test test/milos_training/scheduling/ test/milos_training/application/
  ```

- [ ] **LIVE TEST:**
  - Log in as admin → create 3 time slots for different types
  - Log in as member → filter by type → only matching slots shown
  - Book a slot (auto_approve off) → admin receives in-app notification
  - Admin approves → member sees "Approved" status
  - Book a slot → wait for timeout → admin receives timeout alert
  - Admin logs in and creates a slot directly on `/schedule` calendar (inline)

- [ ] **Update ADR-004** `Implementation Notes`
- [ ] **Update `docs/technical_debt.md`** if needed
- [ ] **Commit & push** (migrations → schemas → domain → commands → queries → application services → API → frontend, in order)

---

## Phase 4: Workout Execution Mode

**Goal:** Members and Athletes can start a workout and enter fullscreen Execution Mode with a step-synced timer, auto-advance, pause/resume, check-offs, score capture per section, and long-press notes.

**Deliverable:** Full Execution Mode UI working on both mobile and desktop. Timer auto-advances correctly for timed sections. Text-linked workout annotations dispatch push stubs to admin.

### File Map

```
apps/api/lib/milos_training/
├── execution/
│   ├── workout_execution.ex
│   ├── domain/
│   │   └── timer_sequence_builder.ex   # Pure Domain
│   ├── commands/
│   │   ├── start_execution.ex
│   │   └── complete_execution.ex
│   ├── queries/
│   │   └── get_execution.ex
│   └── execution.ex
└── application/
    └── complete_workout.ex             # Orchestrates: record + gamification + notifications

apps/web/src/
├── app/workouts/
│   ├── page.tsx                        # Type buttons → week view → workout display
│   └── [id]/
│       └── execute/
│           └── page.tsx               # Execution mode route
├── components/execution/
│   ├── ExecutionMode.tsx              # Fullscreen container
│   ├── TimerDisplay.tsx               # Timer per type (emom, amrap, etc.)
│   ├── WorkoutChecklist.tsx           # Step-by-step rounds
│   ├── ChecklistItem.tsx              # Individual step + long-press handler
│   ├── ScoreModal.tsx                 # Score input on section completion
│   └── NoteModal.tsx                  # Long-press note input
├── hooks/
│   ├── useWorkoutTimer.ts             # Core timer hook
│   └── useExecutionState.ts          # Zustand-backed execution state
└── stores/
    └── executionStore.ts              # Optimistic check-off state
```

### Checklist

- [ ] **Read:** Design doc §7 (Workout Execution Mode), §4 (Flow 2, 3), §5 (workout_executions schema), §2.7 (Optimistic UI pattern)

- [ ] **Write ADR:** Timer architecture (step-synced sequence vs single flat timer — chose sequence for correctness with complex ladder workouts)

- [ ] **Write failing tests for TimerSequenceBuilder (pure Domain)**

- [ ] **Do an online search and create a matrix (data structure) to map out the the workout's (and consequently and timers) sequence for every workout format**

- [ ] **Implement TimerSequenceBuilder (pure Domain)**

- [ ] **Run TimerSequenceBuilder tests — all pass**

- [ ] **Create workout_executions migration and schema**

- [ ] **Create CompleteWorkout Application Service**

- [ ] **Create `useWorkoutTimer` hook** (frontend, key implementation)

- [ ] **Create `executionStore.ts`** (Zustand, optimistic check-offs)

- [ ] **Build `TimerDisplay` component** — renders correct UI per timer type (EMOM countdown, AMRAP countdown, For Time count-up, Tabata work/rest, rest countdown, "No Timer" and all other workout formats)

- [ ] **Build `WorkoutChecklist` + `ChecklistItem`** — expandable sets, text selection annotation flow, right-click / long-press handler (300ms touch hold → `NoteModal`)

- [ ] **Build `ScoreModal`** — appears on scoreable section transition, one input per `score_config.type`

- [ ] **Build fullscreen `ExecutionMode` container** with pause/resume button and 3-second countdown animation

- [ ] **Build `/workouts` browsing page** (`apps/web/src/app/workouts/page.tsx`) — the 3-step discovery flow:

  WeekView is swipeable on mobile via touch events (use `@use-gesture/react`).
  Add `{@use-gesture/react}` to `apps/web/package.json`.

- [ ] **Wire Service Worker cache** for current workout data (offline resilience)

- [ ] **Run full Phase 4 test suite**
  ```bash
  cd apps/api && mix test test/milos_training/execution/ test/milos_training/application/complete_workout_test.exs
  ```

- [ ] **LIVE TEST:**
  - Open a workout → click "Start Workout" → fullscreen activates
  - EMOM timer counts down from 60s → auto-advances to next step at 0
  - Pause → timer freezes → resume → 3-second countdown → timer continues
  - Select text in an exercise label → right-click / long-press → note modal appears → submit note
  - Complete workout → score modal appears for scoreable sections → submit → redirected to landing page

- [ ] **Update the ADR you wrote in the beginning of the phase** `Implementation Notes`
- [ ] **Update `docs/technical_debt.md`** if needed
- [ ] **Commit & push** (domain → commands → application service → hooks → store → components)

---

## Phase 5: Assigned Workouts (Athlete Flow)

**Goal:** Admin can assign master workouts to one or more athletes for a specific date. Athletes see their assigned workouts in a week view and can execute them.

**Deliverable:** `/my-workouts` page fully functional. Admin can assign from `/admin/workouts`.

### File Map

```
apps/api/lib/milos_training/workouts/
├── assigned_workout.ex
├── assigned_workout_athlete.ex       # join table schema
├── commands/
│   └── assign_workout.ex
└── queries/
    └── get_athlete_week_view.ex

apps/web/src/app/
├── my-workouts/
│   └── page.tsx                      # Athlete week view
└── admin/workouts/
    └── [id]/
        └── assign/
            └── page.tsx              # Admin assign form
```

### Checklist

- [ ] **Read:** Design doc §4 (Flow 3), §5 (assigned_workouts, assigned_workout_athletes), §3 (Athlete permission set)

- [ ] **Write ADR-006:** Assigned workouts join table design (one assignment to many athletes via join table vs one record per athlete — chose join table for admin convenience)

- [ ] **Write failing tests for AssignWorkout command**
  ```elixir
  test "assigns workout to multiple athletes" do
    [a1, a2] = insert_athletes(2)
    workout = insert_workout()
    assert {:ok, assignment} = AssignWorkout.call(%{
      master_workout_id: workout.id,
      athlete_ids: [a1.id, a2.id],
      scheduled_for: Date.utc_today()
    })
    assert length(assignment.athletes) == 2
  end
  ```

- [ ] **Create migrations** for assigned_workouts and assigned_workout_athletes

- [ ] **Implement AssignWorkout command, GetAthleteWeekView query**

- [ ] **Add to Workouts context public API**

- [ ] **Create API endpoints:** `POST /api/admin/assigned-workouts`, `GET /api/my-workouts`

- [ ] **Build `/my-workouts` page** — same week-view pattern as `/workouts` but filtered to assigned only, no scale selection (athlete gets base workout), "Execute" button

- [ ] **Build admin assign form** at `/admin/workouts/[id]/assign` — athlete multi-select (fuzzy search), date picker

- [ ] **Run tests**
  ```bash
  cd apps/api && mix test test/milos_training/workouts/
  ```

- [ ] **LIVE TEST:**
  - Log in as admin → assign workout to 2 athletes for tomorrow
  - Log in as athlete 1 → see workout in `/my-workouts` week view
  - Execute it → Execution Mode works normally
  - Log in as athlete 2 → same assignment visible independently

- [ ] **Update ADR-006** `Implementation Notes`
- [ ] **Update `docs/technical_debt.md`** if needed
- [ ] **Commit & push**

---

## Phase 6: Notifications (In-App + Web Push)

**Goal:** All notification events dispatch in-app notifications and Web Push messages. Service Worker installed and functional.

**Deliverable:** All events from §9 of design doc trigger both in-app + push. Notification bell in nav shows unread count. Service Worker registered.

### File Map

```
apps/api/lib/milos_training/
├── notifications/
│   ├── notification.ex
│   ├── push_subscription.ex
│   ├── commands/
│   │   ├── create_notification.ex
│   │   └── save_push_subscription.ex
│   ├── queries/
│   │   └── get_unread.ex
│   └── notifications.ex
└── infrastructure/
    └── workers/
        └── push_dispatch_job.ex        # Oban worker for Web Push

apps/web/public/
└── sw.js                               # Service Worker

apps/web/src/
├── hooks/
│   └── usePushNotifications.ts         # Subscribe/unsubscribe logic
└── components/layout/
    └── NotificationBell.tsx
```

### Checklist

- [ ] **Read:** Design doc §9 (Notifications), §2.7 (Phoenix PubSub Event Bus, Oban Job Chaining), §2.2 (Notifications context boundary)

- [ ] **Write ADR-007:** Web Push delivery (direct from Phoenix vs Oban worker — chose Oban for reliability, retries, and non-blocking response)

- [ ] **Create notifications migration and schema**

- [ ] **Implement PubSub event handlers** for all notification types

  `apps/api/lib/milos_training/notifications/event_handler.ex`:
  ```elixir
  defmodule MilosTraining.Notifications.EventHandler do
    use GenServer

    def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

    def init(_) do
      Phoenix.PubSub.subscribe(MilosTraining.PubSub, "workout:completed")
      Phoenix.PubSub.subscribe(MilosTraining.PubSub, "booking:submitted")
      Phoenix.PubSub.subscribe(MilosTraining.PubSub, "booking:resolved")
      {:ok, []}
    end

    def handle_info({:workout_completed, %{exercise_notes: notes} = execution}, state)
        when length(notes) > 0 do
      MilosTraining.Notifications.Commands.CreateNotification.call(%{
        user_id: admin_user_id(),
        type: :workout_note,
        payload: %{execution_id: execution.id, user_id: execution.user_id}
      })
      dispatch_push(:workout_note, admin_user_id(), execution)
      {:noreply, state}
    end

    def handle_info(_, state), do: {:noreply, state}

    defp dispatch_push(type, user_id, payload) do
      MilosTraining.Workers.PushDispatchJob.new(%{
        "type" => to_string(type),
        "user_id" => user_id,
        "payload" => payload
      }) |> Oban.insert()
    end

    defp admin_user_id, do: MilosTraining.Identity.Queries.FindUser.admin_id()
  end
  ```

- [ ] **Implement PushDispatchJob** (Oban worker using `web_push_elixir`)

  Add to `apps/api/mix.exs`: `{:web_push_elixir, "~> 0.3"}`

  ```elixir
  defmodule MilosTraining.Workers.PushDispatchJob do
    use Oban.Worker, queue: :notifications, max_attempts: 3

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"user_id" => user_id} = args}) do
      subscriptions = MilosTraining.Notifications.get_push_subscriptions(user_id)
      payload = Jason.encode!(%{type: args["type"], payload: args["payload"]})

      Enum.each(subscriptions, fn sub ->
        WebPushElixir.send_notification(sub.endpoint, sub.keys["p256dh"],
          sub.keys["auth"], payload)
      end)
    end
  end
  ```

- [ ] **Create Service Worker** (`apps/web/public/sw.js`)
  ```javascript
  self.addEventListener("push", (event) => {
    const data = event.data?.json() ?? {}
    event.waitUntil(
      self.registration.showNotification(data.title ?? "Gym App", {
        body: data.body ?? "",
        icon: "/icons/icon-192.png",
        data: data.url ? { url: data.url } : undefined,
      })
    )
  })

  self.addEventListener("notificationclick", (event) => {
    event.notification.close()
    if (event.notification.data?.url) {
      event.waitUntil(clients.openWindow(event.notification.data.url))
    }
  })
  ```

- [ ] **Create `usePushNotifications` hook** (register SW, subscribe to push, POST subscription to API)

- [ ] **Build `NotificationBell` component** (fetches unread count via TanStack Query, Phoenix Channel subscription for real-time updates)

- [ ] **Run tests**
  ```bash
  cd apps/api && mix test test/milos_training/notifications/
  ```

- [ ] **LIVE TEST:**
  - Register SW in browser (accept push permission prompt)
  - Admin approves a booking → member receives push notification in browser
  - Member submits a workout note → admin receives push notification
  - Notification bell shows correct unread count
  - Click notification → navigates to relevant page

- [ ] **Update ADR-007** `Implementation Notes`
- [ ] **Update `docs/technical_debt.md`** if needed
- [ ] **Commit & push**

---

## Phase 7: Gamification

**Goal:** Streak Engine, PR Board, Seasonal Challenges, and opt-in Leaderboard all functional and displayed on the Landing Page.

**Deliverable:** Landing Page fully operational with gamification panel. Admin can create challenges from `/admin/challenges`.

### File Map

```
apps/api/lib/milos_training/
├── gamification/
│   ├── user_stats.ex
│   ├── user_achievement.ex
│   ├── seasonal_challenge.ex
│   ├── user_challenge_progress.ex
│   ├── leaderboard_opt_in.ex
│   ├── domain/
│   │   ├── streak_calculator.ex        # Pure Domain
│   │   └── pr_detector.ex              # Pure Domain
│   ├── commands/
│   │   ├── update_stats.ex
│   │   ├── award_badge.ex
│   │   └── record_pr.ex
│   ├── queries/
│   │   ├── get_user_stats.ex
│   │   ├── get_leaderboard.ex          # Reads materialized view
│   │   └── get_active_challenges.ex
│   └── gamification.ex
└── infrastructure/
    └── workers/
        └── refresh_leaderboard_job.ex  # Refreshes MATERIALIZED VIEW every 15min

apps/web/src/
├── app/page.tsx                        # Landing page
└── components/landing/
    ├── GamificationPanel.tsx
    ├── StreakCounter.tsx
    ├── BadgeGrid.tsx
    ├── ChallengeProgress.tsx
    ├── LeaderboardSnippet.tsx
    └── MembershipCard.tsx
```

### Checklist

- [ ] **Read:** Design doc §6 (Gamification), §5 (gamification data models), §2.7 (PostgreSQL Materialized Views, Redis Cache-Aside)

- [ ] **Write ADR-008:** Streak calculation trigger (on-write via CompleteWorkout Application Service vs scheduled recalculation — chose on-write for immediate feedback; weekly consistency score recalculated nightly via Oban)

- [ ] **Write failing tests for StreakCalculator (pure Domain)**
  ```elixir
  defmodule MilosTraining.Gamification.Domain.StreakCalculatorTest do
    use ExUnit.Case, async: true
    alias MilosTraining.Gamification.Domain.StreakCalculator

    test "streak increments when current week has >= target workouts" do
      stats = %{current_streak: 3, last_workout_at: last_week()}
      result = StreakCalculator.update(stats, target: 2, workouts_this_week: 2)
      assert result.current_streak == 4
    end

    test "streak resets when week missed with no shield" do
      stats = %{current_streak: 5, current_streak_shields: 0, last_workout_at: two_weeks_ago()}
      result = StreakCalculator.update(stats, target: 2, workouts_this_week: 3)
      assert result.current_streak == 1
    end

    test "shield consumed instead of reset" do
      stats = %{current_streak: 5, current_streak_shields: 1, last_workout_at: two_weeks_ago()}
      result = StreakCalculator.update(stats, target: 2, workouts_this_week: 3)
      assert result.current_streak == 6
      assert result.current_streak_shields == 0
    end
  end
  ```

- [ ] **Implement StreakCalculator and PRDetector (pure Domain)**

- [ ] **Write failing tests for PRDetector**
  ```elixir
  test "detects PR when new score better than all previous for same section" do
    history = [%{section_id: "s1", value: 300, score_type: :time}]
    new_score = %{section_id: "s1", value: 250, score_type: :time}
    assert PRDetector.is_pr?(new_score, history, lower_is_better: [:time])
  end
  ```

- [ ] **Create all gamification migrations** (user_stats, user_achievements, seasonal_challenges, user_challenge_progress, leaderboard_opt_ins)

- [ ] **Create PostgreSQL materialized view for leaderboard**

  ```sql
  -- In migration:
  execute """
  CREATE MATERIALIZED VIEW weekly_leaderboard AS
    SELECT
      u.id AS user_id,
      u.nickname,
      COUNT(we.id) AS workouts_this_week,
      COUNT(ua.id) FILTER (
        WHERE ua.earned_at >= date_trunc('week', NOW())
        AND ua.badge_key LIKE 'pr_%'
      ) AS prs_this_month
    FROM users u
    JOIN leaderboard_opt_ins lo ON lo.user_id = u.id
    LEFT JOIN workout_executions we ON we.user_id = u.id
      AND we.completed_at_utc >= date_trunc('week', NOW())
    LEFT JOIN user_achievements ua ON ua.user_id = u.id
    GROUP BY u.id, u.nickname
    ORDER BY workouts_this_week DESC
  WITH NO DATA;
  """

  execute "CREATE UNIQUE INDEX ON weekly_leaderboard (user_id);"
  ```

- [ ] **Implement RefreshLeaderboardJob** (Oban, every 15 minutes)

  ```elixir
  defmodule MilosTraining.Workers.RefreshLeaderboardJob do
    use Oban.Worker, queue: :analytics

    @impl Oban.Worker
    def perform(_job) do
      MilosTraining.Repo.query!("REFRESH MATERIALIZED VIEW CONCURRENTLY weekly_leaderboard")
      :ok
    end
  end
  ```

  Schedule in `config.exs`:
  ```elixir
  config :milos_training, Oban,
    crontab: [
      {"*/15 * * * *", MilosTraining.Workers.RefreshLeaderboardJob}
    ]
  ```

- [ ] **Implement Redis Cache-Aside for Landing Page**

  `apps/api/lib/milos_training/infrastructure/cache/landing_cache.ex`:
  ```elixir
  defmodule MilosTraining.Infrastructure.Cache.LandingCache do
    @ttl 60  # seconds

    def get_or_fetch(user_id, fetch_fn) do
      key = "landing:#{user_id}"
      case Redix.command(:redix, ["GET", key]) do
        {:ok, nil} ->
          data = fetch_fn.()
          Redix.command(:redix, ["SETEX", key, @ttl, Jason.encode!(data)])
          data
        {:ok, cached} -> Jason.decode!(cached, keys: :atoms)
      end
    end

    def invalidate(user_id) do
      Redix.command(:redix, ["DEL", "landing:#{user_id}"])
    end
  end
  ```

  Call `LandingCache.invalidate(user_id)` in `CompleteWorkout` Application Service after gamification update.

- [ ] **Build Landing Page** with GamificationPanel, StreakCounter, BadgeGrid, ChallengeProgress, LeaderboardSnippet, MembershipCard

- [ ] **Build workout history modal** on Landing Page — `WorkoutHistoryModal.tsx`:
  - Triggered by clicking any entry in the scrollable workout history list
  - Fetches `GET /api/executions/:id` (full execution details)
  - Displays: workout title, date, scale level, sections with scores
  - **Modifications/notes highlighted prominently in color** (e.g., amber background + left border)
    ```typescript
    // In WorkoutHistoryModal, for each exercise note:
    <div className="bg-amber-50 border-l-4 border-amber-400 px-3 py-2 rounded">
      <span className="font-medium">{note.word}</span>: {note.note_text}
    </div>
    ```
  - Admin sees all users' history from coaching drill-down (same modal, different data source)

- [ ] **Build `/admin/challenges` page** (create challenge form: title, description, date range, criteria, badge label; list active challenges with user progress counts)

- [ ] **Run full test suite**
  ```bash
  cd apps/api && mix test test/milos_training/gamification/
  ```

- [ ] **LIVE TEST:**
  - Complete 2 workouts in one week → streak increments on Landing Page
  - Beat a previous score → PR badge appears
  - Admin creates a seasonal challenge → appears in member's Landing Page with progress bar
  - Opt into leaderboard → appear in leaderboard snippet
  - Refresh materialized view manually → `REFRESH MATERIALIZED VIEW CONCURRENTLY weekly_leaderboard` → leaderboard updates

- [ ] **Update ADR-008** `Implementation Notes`
- [ ] **Update `docs/technical_debt.md`** if needed
- [ ] **Commit & push**

---

## Phase 8: Admin Dashboard & Analytics

**Goal:** Admin can view financial analytics, coaching analytics, and drill down to any user with fuzzy Meilisearch search.

**Deliverable:** `/admin` fully functional with both tabs. Meilisearch indexes synced. Fuzzy search returns results in < 50ms.

### File Map

```
apps/api/lib/milos_training/
├── coaching/
│   ├── admin_athlete_note.ex
│   ├── commands/
│   │   └── write_note.ex
│   ├── queries/
│   │   ├── get_coaching_aggregates.ex   # Reads coaching_aggregates matview
│   │   └── get_athlete_drill_down.ex
│   └── coaching.ex
└── infrastructure/
    ├── search/
    │   └── member_indexer.ex             # Meilisearch sync
    └── workers/
        └── index_user_job.ex             # Oban: index on user create/update

apps/web/src/
├── app/admin/
│   └── page.tsx                          # Dashboard tabs
└── components/admin/
    ├── FinancialTab.tsx
    ├── CoachingTab.tsx
    ├── FuzzySearchBar.tsx                # Meilisearch live suggestions
    ├── MemberDrillDown.tsx
    └── AthleteDrillDown.tsx
```

### Checklist

- [ ] **Read:** Design doc §4 (Flows 5, 6, 7), §8 (Page-by-Page — /admin), §10 Tech Stack (Meilisearch)

- [ ] **Write ADR-009:** Analytics read strategy (PostgreSQL materialized views for aggregates vs ad-hoc queries — chose matviews for < 200ms response on dashboard load)

- [ ] **Create coaching_aggregates materialized view** (similar pattern to weekly_leaderboard)

- [ ] **Configure Meilisearch** — create `users` index with searchable/filterable attributes

  `apps/api/lib/milos_training/infrastructure/search/member_indexer.ex`:
  ```elixir
  defmodule MilosTraining.Infrastructure.Search.MemberIndexer do
    @index "users"

    def index_user(user) do
      doc = %{id: user.id, nickname: user.nickname, role: user.role}
      Meilisearch.Document.add_or_update(@index, [doc])
    end

    def search(query, opts \\ []) do
      Meilisearch.Search.search(@index, query, Keyword.merge([limit: 10], opts))
    end
  end
  ```

  Add `{:meilisearch, "~> 0.5"}` to `apps/api/mix.exs`.

- [ ] **Create IndexUserJob** (Oban — triggered from `RegisterUser` command via PubSub)

- [ ] **Create all coaching migrations** (admin_athlete_notes), coaching context, commands, queries

- [ ] **Create API endpoints** for admin dashboard (financial summary, coaching aggregates, member/athlete drill-down, write note)

- [ ] **Build `/admin` page** with:
  - Tab 1: `FinancialTab` — Recharts revenue chart, active memberships count, expiring-soon list, `FuzzySearchBar` → `MemberDrillDown` (edit membership inline)
  - Tab 2: `CoachingTab` — frequency trends, inactive alerts, `FuzzySearchBar` → `AthleteDrillDown` (timeline, scores, notes, write note)

- [ ] **FuzzySearchBar** — debounced 200ms, calls `GET /api/admin/search?q=` → renders dropdown suggestions

- [ ] **Run tests**
  ```bash
  cd apps/api && mix test test/milos_training/coaching/
  ```

- [ ] **LIVE TEST:**
  - Type "ath" in fuzzy search → live Meilisearch suggestions within 50ms
  - Click athlete → drill-down shows workout history, scores with chart, any notes
  - Admin writes a note → athlete sees it on their Landing Page
  - Financial tab shows correct revenue sum and expiring memberships

- [ ] **Update ADR-009** `Implementation Notes`
- [ ] **Update `docs/technical_debt.md`** if needed
- [ ] **Commit & push**

---

## Phase 9: PWA, Performance & Production Hardening

**Goal:** App works offline in Execution Mode, passes WCAG 2.1 AA, loads Landing Page in < 200ms, and is production-ready on own server.

**Deliverable:** PWA installable on mobile. Lighthouse score ≥ 90. All Redis cache-aside paths verified. Rate limiting verified. Docker Compose prod config complete.

### File Map

```
apps/web/public/
├── manifest.json
├── sw.js                              # Extended with workout cache strategy
└── icons/
    ├── icon-192.png
    └── icon-512.png

apps/web/src/
├── app/about/
│   └── page.tsx                       # Know More / marketing page
└── components/
    └── accessibility/
        └── SkipToContent.tsx

apps/api/
├── config/
│   └── prod.exs                       # Production Phoenix config
└── rel/
    └── env.sh.eex                     # Runtime env vars

docker-compose.prod.yml                # Production overrides
```

### Checklist

- [ ] **Read:** Design doc §11 (Non-Functional Requirements), §1 (Design principles: minimal, colorful, uncluttered)

- [ ] **Write ADR-010:** PWA strategy (Service Worker caching for Execution Mode offline resilience — chose cache-first for workout data, network-first for API)

- [ ] **Create `manifest.json`**
  ```json
  {
    "name": "Gym App",
    "short_name": "MilosTraining",
    "start_url": "/",
    "display": "standalone",
    "background_color": "#ffffff",
    "theme_color": "#000000",
    "icons": [
      { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
      { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" }
    ]
  }
  ```

- [ ] **Extend Service Worker** with workout cache strategy:
  - Cache-first for `/api/workouts/:id` responses (execution mode resilience)
  - Network-first for all other API calls
  - Stale-while-revalidate for static assets

- [ ] **Build `/about` page** — static marketing page (public, no auth required)

- [ ] **Verify Redis cache-aside** — confirm Landing Page hits Redis on 2nd request:
  ```bash
  docker exec -it gym_redis redis-cli MONITOR
  # Load Landing Page → should see SETEX on first load, GET hit on second
  ```

- [ ] **Run Lighthouse audit**
  ```bash
  npx lighthouse http://localhost --output=json --quiet | jq '.categories | {perf: .performance.score, a11y: .accessibility.score, pwa: .pwa.score}'
  # Target: all >= 0.90
  ```

- [ ] **Fix all WCAG 2.1 AA violations** from Lighthouse accessibility report (color contrast on difficulty badges, keyboard nav on calendar, aria-labels on icon buttons)

- [ ] **Add `docker-compose.prod.yml`** (no volume mounts, restart: always, no dev ports exposed)

- [ ] **Configure production Phoenix** in `config/prod.exs` (secret_key_base from env, database SSL, port 4000)

- [ ] **Verify rate limiting end-to-end** — hit login 11 times rapidly → 429 response

- [ ] **Run full test suite — all green**
  ```bash
  cd apps/api && mix test
  cd apps/web && npm run build && npm test
  ```

- [ ] **LIVE TEST (full system):**
  - Full registration → login → book class → receive push notification → complete workout → score saved → gamification updated → Landing Page reflects new streak/PRs
  - Put browser offline → start workout → complete it → come back online → execution synced
  - Install app on mobile (PWA "Add to Home Screen") → launches in standalone mode
  - All pages keyboard-navigable

- [ ] **Update ADR-010** `Implementation Notes`
- [ ] **Final pass on `docs/technical_debt.md`** — ensure all known deferred items documented
- [ ] **Final ADR audit** — all ADRs have `Implementation Notes` filled in
- [ ] **Commit & push:**
  ```
  feat(pwa): add web app manifest and SW caching for offline execution mode
  feat(about): add /about marketing page
  fix(a11y): fix WCAG 2.1 AA violations (contrast, keyboard nav, aria)
  chore(prod): add docker-compose.prod.yml and Phoenix prod config
  docs(adr): fill implementation notes for all ADRs
  docs(debt): final technical debt ledger pass
  ```

---

## Phase Summary

| Phase | Goal | Key Deliverable |
|---|---|---|
| 0 | Scaffold | `docker compose up` works, health endpoint live |
| 1 | Identity | Register, login, JWT, role-based auth |
| 2 | Workouts | Workout CRUD, materialization engine, admin UI |
| 3 | Scheduling | Calendar, booking flow, Oban timeouts |
| 4 | Execution | Timer-synced fullscreen mode, check-offs, scores |
| 5 | Athletes | Assigned workouts, athlete week view |
| 6 | Notifications | In-app bell + Web Push for all events |
| 7 | Gamification | Streak, PRs, challenges, leaderboard, Landing Page |
| 8 | Admin | Analytics dashboard, Meilisearch fuzzy search |
| 9 | Hardening | PWA, WCAG AA, Redis verified, prod config |

---

## Open Items (from spec §12)

- App name: TBD — update `manifest.json`, `mix.exs`, `package.json` when confirmed
- Scale level labels ("Beginner/Intermediate/Advanced" vs "Scaled/Rx/Rx+") — **decide before Phase 2 migration runs** — cannot change without a new migration
- Color palette for difficulty coding — decide before Phase 2 frontend. Suggestion: 🟢 #22c55e Beginner / 🟡 #eab308 Intermediate / 🔴 #ef4444 Advanced
