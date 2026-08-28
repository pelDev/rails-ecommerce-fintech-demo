# B2B Payment Platform

A production-oriented payment platform for fintech serving B2B eCommerce
merchants. Merchants sign up, generate API credentials, create orders and
initiate payments through a REST API, watch payment status updates arrive
asynchronously (simulated provider webhooks), and manage everything from a
dashboard with a live Test Console.

Built for a senior full-stack assessment: **correctness, security, reliability,
and data consistency are treated as more important than feature breadth** —
see [docs/assumptions.md](docs/assumptions.md) and
[docs/architecture.md](docs/architecture.md) for the full design contract.

## Feature checklist (per the brief)

| Requirement | Where |
|---|---|
| Create orders | `POST /api/v1/orders` → `OrderCreationForm` |
| Initiate payments against orders | `POST /api/v1/orders/:order_id/payments` → `PaymentInitiationService` |
| Receive payment status updates | Simulated provider webhook → `WebhookProcessor` → AASM transition |
| Handle asynchronous provider notifications | `WebhookEvent` inbox (exactly-once, deduped, retried) |
| Dashboard for orders & payments | `/` (metrics + recent orders/payments), `/orders/new` Test Console |
| Mock payment provider | `PaymentProvider::StripeAdapter` / `PaypalAdapter` + `StripeWebhookSimulator` |

## Tech stack

| Layer | Choice |
|---|---|
| Language / framework | Ruby 3.4.10 · Rails 8.1.3 |
| Database | PostgreSQL 16 (ActiveRecord, DB-level check constraints & partial indexes) |
| State machines | AASM (`Order`, `Payment`) |
| Auth | Devise (dashboard) · custom API key/secret (`ApiCredential`) |
| Async jobs | SolidQueue (production) · in-process `:async` (dev/test) |
| Serialization | `jsonapi-serializer` |
| Front-end | Hotwire (Turbo + Stimulus) + Tailwind |
| Testing | RSpec |
| Infra | Docker Compose (dev) · Dockerfile + Kamal (prod) |

## Repository layout

```
app/
  controllers/api/v1/     # token-authenticated REST API
  controllers/            # dashboard, orders (Test Console), api_credentials
  forms/                  # OrderCreationForm, MerchantSignupForm
  services/
    payment_provider/     # BaseAdapter, StripeAdapter, PaypalAdapter (mock seam)
    payment_initiation_service.rb
    webhook_processor.rb  # exactly-once webhook handling
    stripe_webhook_simulator.rb
    merchant_notifier.rb
  jobs/                   # WebhookSimulationJob
  models/                 # merchant, user, api_credential, order, order_item,
                          # payment, webhook_event (+ AASM state machines)
  serializers/            # PaymentSerializer
db/schema.rb              # authoritative schema incl. check constraints
spec/                     # RSpec model / request / job / view specs
docs/                     # assumptions.md, architecture.md, test-console-flow.md
docker-compose.yml        # local dev stack (db + web)
```

## Quick start

### Option A — Docker Compose (recommended)

Prerequisites: Docker with Compose v2.

```bash
cp .env.example .env        # fill in RAILS_MASTER_KEY (or leave blank; master.key is mounted)
docker compose up --build -d
docker compose ps           # wait for db healthy + web up
open http://localhost:3000
```

The `web` service runs `db:prepare` (creates/migrates the dev database) and
compiles Tailwind before booting Puma on port 3000. Healthcheck:
`http://localhost:3000/up`. The container runs `Dockerfile.dev` — a dev-only
image with **all** gem groups installed (so RSpec, RuboCop, Brakeman work
inside the container) — and your code is bind-mounted, so edits hot-reload.

First use: sign up at `/users/sign_up` (creates a merchant + user), then generate
an API credential on `/api_credentials` — the raw secret is shown **once**.

> Code changes need no rebuild (bind mount). Only Gemfile/Gemfile.lock changes
> require `docker compose build web && docker compose up -d`.

### Option B — Local (no Docker)

Prerequisites: Ruby 3.4.10 (e.g. via mise/rbenv), PostgreSQL running locally,
Node (for Tailwind).

```bash
bundle install
bin/rails db:prepare         # creates + migrates dev DB
bin/dev                      # web + Tailwind watcher (Procfile.dev)
open http://localhost:3000
```

`config/database.yml` connects over the local socket by default; set
`DATABASE_URL` to override.

## Tests & quality gates

```bash
# Docker
docker compose exec -e DATABASE_URL=postgres://postgres:postgres@db:5432/ecommerce_demo_test \
  web bin/rails db:prepare
docker compose exec -e DATABASE_URL=postgres://postgres:postgres@db:5432/ecommerce_demo_test \
  web bundle exec rspec

# Local
bundle exec rspec

# Static checks
bin/rubocop
bin/brakeman
bin/bundler-audit
```

## Documentation

- **[docs/assumptions.md](docs/assumptions.md)** — every design assumption, scope cut, and production gap, one row at a time.
- **[docs/architecture.md](docs/architecture.md)** — components, data model, state machines, request flows, security & consistency model, decision log.
- **[docs/test-console-flow.md](docs/test-console-flow.md)** — how the Test Console exercises the API.

## API reference (v1)

Base URL: `http://localhost:3000/api/v1` · Auth: `X-Api-Key` + `X-Api-Secret` headers · TLS assumed at the edge.

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/orders/ping` | Unauthenticated liveness probe |
| `GET` | `/api/v1/orders` | List merchant orders |
| `POST` | `/api/v1/orders` | Create an order (server-computed total) |
| `POST` | `/api/v1/orders/:order_id/payments` | Initiate a payment (idempotency-key aware) |
| `GET` | `/api/v1/orders/:order_id/payments` | List payments for an order |

```bash
curl -s http://localhost:3000/api/v1/orders/ping

# Create an order
curl -s -X POST http://localhost:3000/api/v1/orders \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <key>" -H "X-Api-Secret: <secret>" \
  -d '{"order":{"currency":"USD","external_reference":"ORD-1001",
       "order_items_attributes":[{"product_name":"Widget","quantity":2,"unit_price_cents":500}]}}'

# Initiate a payment against it (amount must equal the order total)
curl -s -X POST http://localhost:3000/api/v1/orders/<order_id>/payments \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <key>" -H "X-Api-Secret: <secret>" \
  -d '{"payment_method":"card","idempotency_key":"pay-ORD-1001-1"}'
```

In dev/test the simulated provider webhook fires ~10 seconds later and settles the
payment (`succeeded` ~80% / `failed` ~20%); the dashboard and Test Console update
in real time via Turbo Streams.

## What I would have done with more time

1. **Real webhook transport.** Today notifications are simulated in-process; a
   production build would add a signed `POST /webhooks/:provider` endpoint with
   HMAC verification, provider-side replay protection, and per-merchant delivery
   URLs.
2. **Outbox + DLQ for guaranteed delivery.** Persist outbound notifications in an
   outbox table, dispatch via a worker with exponential backoff, dead-letter
   after N attempts, and expose a replay UI.
3. **Mandatory idempotency keys** with full `Idempotency-Key` header semantics
   (store the original response, return it for replays, enforce TTL).
4. **Refunds, partial captures, and multi-currency** — provider-level refunds,
   FX conversion, and a double-entry ledger with daily reconciliation against
   provider reports.
5. **Hardened API auth** — HMAC request signing instead of bearer-style
   key/secret, credential rotation workflow, IP allowlists, and tuned
   `rack-attack` throttling (declared but not configured).
6. **Real authorization** — wire up Pundit policies (declared but not used) and
   add role-based dashboard permissions.
7. **Out-of-transaction provider calls** — move the provider HTTP call out of the
   DB transaction (outbox / SAGA) to avoid long-held locks, with compensating
   actions for partial failures.
8. **Observability** — structured JSON logs, payment/order metrics (success rate,
   processing time), distributed tracing, and error tracking (e.g. Sentry).
9. **Pagination, filtering, and sorting** on the API list endpoints, plus
   merchant-facing webhook delivery logs.
10. **End-to-end CI** — a pipeline that builds the Docker image, boots the
    Compose stack, runs RSpec against it, and fails on schema drift.

## Placeholders, mocks, and workarounds

This section is deliberately honest about every shortcut taken so the assessment
scope is clear.

| Area | Current state | What production needs |
|---|---|---|
| Payment provider | Mock only. `StripeAdapter` always returns `processing` (random-outcome line commented out); `PaypalAdapter` randomizes locally. | Real provider sandboxes + live keys behind the same `BaseAdapter` interface. |
| Provider dispatch | `PaymentInitiationService#provider_adapter_for` returns `StripeAdapter` for **all** payment methods (dispatch table commented out). | Map `payment_method` → adapter. |
| **Webhooks sent/received** | **None over HTTP.** `WebhookSimulationJob` + `StripeWebhookSimulator` create the event in-process ~10s after initiation; the *processing* pipeline (persist → dedup → exactly-once transition) is real, the *transport* is not. | Signed HTTP endpoint, signature verification, retries/backoff, DLQ, outbox. |
| Webhook signatures | `signature: 'simulated_signature'` placeholder. | Verify the provider's signature before trusting payloads. |
| Merchant notification | `MerchantNotifier` broadcasts via Turbo Streams in dev/test; the production delivery path is a commented-out `WebhookDeliveryJob`. | HTTP delivery job + retries + delivery logs. |
| Job adapter | Dev/test run on Rails' in-process `:async` adapter; SolidQueue only in production. | SolidQueue worker process in the dev stack (see commented `worker` service in `docker-compose.yml`). |
| Retry machinery | Retry caps and backoff constants exist (`WebhookEvent`, `Payment`), but the jobs they enqueue (`WebhookEventJob`, `PaymentProcessorJob`) are **not implemented** — see Known gaps. | Implement the retry jobs or replace with SolidQueue retry config. |
| Docker dev workflow | Dev image (`Dockerfile.dev`, all gem groups) + bind-mounted code for hot reload; `DATABASE_URL` override keeps the test DB separate from dev; production `Dockerfile` untouched for Kamal. | SolidQueue worker in the dev stack for production-like runs; cache service. |
| Rate limiting / authorization | `rack-attack` and Pundit are declared in the Gemfile but not wired up. | Configure throttles; implement policies. |
| TLS | Assumed terminated at the edge. | Enforce HTTPS, HSTS, certificate pinning where applicable. |

## Known gaps (self-review findings)

Found while writing this documentation — included for transparency, not fixed:

1. **`Order#expired` maps to enum value `6`, but the DB check constraint
   `orders_status_valid_check` only allows `0..5`** — `expire!` raises at the DB
   level. The constraint must be widened to include `6`.
2. **`WebhookEvent#process_payload!` / `find_or_process` are not exercised** by
   the simulator flow (which uses `WebhookProcessor`); if wired up, they call
   `Payment` methods that don't exist (`mark_as_completed!`, `status_pending?`).
3. **`WebhookEventJob` and `PaymentProcessorJob` are referenced but not
   implemented** (see Placeholders above) — any code path that enqueues them
   (`WebhookEvent#process!` retry, `WebhookEvent.retry_failed`,
   `Payment#retry`) will raise `NameError`.
4. CI not passing as it was ignored for this submission iteration.
