# Architecture

This document describes the structure, data model, request flows, and reliability
properties of the B2B payment platform. It is the companion to
[assumptions.md](./assumptions.md) — read that first for the design contract.

## 1. Overview

A Rails 8.1 monolith exposing:

- a **public REST API** (`/api/v1`) for merchants to create orders and initiate
  payments, authenticated with API key + secret;
- a **dashboard** (Devise-authenticated) for merchants to view orders/payments,
  manage API credentials, and drive a live **Test Console**;
- a **mock payment provider** that settles payments asynchronously through a
  simulated webhook pipeline, persisted for audit and processed exactly-once.

```
                    ┌────────────────────────────────────────────────┐
                    │                Rails 8.1 App (Puma)             │
                    │                                                │
  Merchant API      │   ┌─────────────┐      ┌────────────────────┐   │
  client ─────────► │   │ API::V1     │─────►│ PaymentInitiation  │   │
  (X-Api-Key/Secret)│   │ controllers │      │ Service            │   │
                    │   └─────────────┘      └─────────┬──────────┘   │
                    │                                 │              │
  Browser ────────► │   ┌─────────────┐               ▼              │
  (Devise login)    │   │ Dashboard / │      ┌────────────────────┐   │
                    │   │ Test Console│      │ PaymentProvider::  │   │
                    │   └─────────────┘      │ *Adapter (mock)    │   │
                    │         │              └─────────┬──────────┘   │
                    │         │                        │              │
                    │         ▼                        ▼              │
                    │   ┌─────────────────────────────────────────┐   │
                    │   │             PostgreSQL (single DB)      │   │
                    │   │  merchants users api_credentials        │   │
                    │   │  orders order_items payments            │   │
                    │   │  webhook_events                         │   │
                    │   └─────────────────────────────────────────┘   │
                    │         ▲                                      │
                    │         │ (async job, +10s, dev/test)          │
                    │   ┌─────────────────────────────────────────┐   │
                    │   │ WebhookSimulationJob ──► StripeWebhook   │   │
                    │   │ Simulator ──► WebhookEvent ──►           │   │
                    │   │ WebhookProcessor (exactly-once)          │   │
                    │   └─────────────────────────────────────────┘   │
                    └────────────────────────────────────────────────┘
```

## 2. Stack

| Layer | Choice | Why |
|-------|--------|-----|
| Language / framework | Ruby 3.4.10, Rails 8.1.3 | Required by the brief |
| Database | PostgreSQL 16, ActiveRecord | Required; DB-level check constraints + partial indexes for integrity/perf |
| State machines | AASM | Guarded, auditable transitions for `Order` and `Payment` |
| Auth (web) | Devise | Dashboard auth, roles, lockout/trackable |
| Auth (API) | Custom token auth via `ApiCredential` | Key/secret over HTTPS, BCrypt-hashed secrets |
| Serialization | `jsonapi-serializer` | Stable JSON:API-ish shape for payments |
| Background jobs | SolidQueue (production), `:async` (dev/test) | DB-backed queue, no extra infra |
| Real-time (dev/test) | Turbo Streams broadcast | Test Console event feed |
| Front-end | Hotwire (Turbo + Stimulus) + Tailwind | Server-rendered dashboard with live updates |
| Testing | RSpec | Model / request / job / view specs |
| Infra | Dockerfile + Kamal, Docker Compose (dev) | Reproducible deploy + local stack |

## 3. Components

### 3.1 Web layer

| Component | Responsibility |
|-----------|----------------|
| `Users::RegistrationsController` | Merchant self-signup via `MerchantSignupForm` (creates `Merchant` + `User` in one transaction) |
| `DashboardController` | Merchant-scoped metrics (total volume, pending orders, successful payments) + recent orders/payments |
| `OrdersController#new` | Test Console page (`app/views/orders/new.html.erb`) with a Stimulus `test-console` controller |
| `ApiCredentialsController` | Generate (key + one-time raw secret), list, and revoke credentials |
| `Api::V1::BaseController` | `X-Api-Key`/`X-Api-Secret` authentication, merchant-active check, scoped `current_merchant` |
| `Api::V1::OrdersController` | `POST /api/v1/orders` (via `OrderCreationForm`), `GET /api/v1/orders`, `GET /api/v1/orders/ping` |
| `Api::V1::PaymentsController` | `POST /api/v1/orders/:order_id/payments`, `GET /api/v1/orders/:order_id/payments` |

### 3.2 Services (the business core)

| Service | Responsibility |
|---------|----------------|
| `OrderCreationForm` | Validates line items, computes the order total server-side, persists order + items in a transaction |
| `MerchantSignupForm` | Validates merchant + user, creates both in a transaction |
| `PaymentInitiationService` | Orchestrates a payment: validations → idempotency check → transactional create + provider call + state transition. Returns a `Result` object (`success`/`payment`/`error`/`error_code`/`metadata`) — never raises for expected failures |
| `PaymentProvider::BaseAdapter` | Adapter contract: `initiate_payment` returns a normalized hash (`status`, `provider_reference`, `failure_reason`) |
| `PaymentProvider::StripeAdapter` / `PaypalAdapter` | Mock implementations; Stripe always returns `processing` (async settle) |
| `StripeWebhookSimulator` | Builds a realistic Stripe-shaped payload, creates the `WebhookEvent`, and hands it to `WebhookProcessor` |
| `WebhookProcessor` | Routes `payment_intent.succeeded` / `payment_intent.payment_failed` / `refund.succeeded` to the matching payment transition |
| `MerchantNotifier` | Dev/test: Turbo Stream broadcast to the merchant's Test Console; production: stub (comment) for a future delivery job |
| `WebhookSimulationJob` | Background job that triggers the simulated webhook ~10s after initiation |

### 3.3 Domain model

| Model | Notes |
|-------|-------|
| `Merchant` | `active | inactive | suspended`; owns everything below |
| `User` | Devise; roles `user | admin | super_admin`; belongs to a merchant |
| `ApiCredential` | `key` (unique) + `secret_digest` (BCrypt, cost 12); `active` flag, `revoked_at`, 90-day `expires_at`; `ApiCredential.authenticate(key, secret)` |
| `Order` | AASM `pending → paid → shipped → delivered`, plus `cancelled | refunded | expired`; status timestamps per terminal state; `external_reference` unique; server-computed `amount_cents` |
| `OrderItem` | Line item; DB check `total_price_cents = quantity * unit_price_cents` |
| `Payment` | AASM `created → pending → processing → succeeded | failed`, `refunded`; `provider_reference` unique & required on success; `failure_reason` required on failure; `idempotency_key` unique per order; retry cap 3; status timestamps |
| `WebhookEvent` | Exactly-once inbox: unique `provider_event_id`, payload + signature, `pending → processing → completed | failed`; retry cap 3 with 5-min backoff |

### 3.4 State machines

**Order**

```
pending ──mark_paid──► paid ──mark_shipped──► shipped ──mark_delivered──► delivered
   │                     │  │
   ├──cancel──► cancelled│  └──refund──► refunded
   │                     └──cancel──► cancelled
   └──expire──► expired
```

Guards: `paid` only via successful payment (`payments.successful.exists?`); cancel only before shipping; refund only when paid; expire only after 24h pending.

**Payment**

```
created ──mark_pending──► pending ──mark_processing──► processing ──succeed──► succeeded
   │                        │  │                              │
   │                        │  └──────────fail───────────────┼──► failed
   └────────────────────────┴────────────────────────────────┘       │
   failed ──retry (≤3)──► pending                                   refunded ◄──refund── succeeded
```

Guards: `succeed` requires a `provider_reference`; `fail` requires a `failure_reason`; `retry` max 3 attempts. `succeed` triggers `order.mark_paid!` and `MerchantNotifier`; `fail` increments `retry_count`.

## 4. Request flows

### 4.1 Create order (`POST /api/v1/orders`)

```
Client ── X-Api-Key/Secret ──► BaseController#authenticate_api_credential!
  ──► OrdersController#create ──► OrderCreationForm#save
        ├─ validate merchant, currency, ≥1 item, item fields, ref uniqueness
        └─ transaction: order.build(status: pending) + order_items.build(...)
  ◄── 201 { success, order: {..., order_items: [...]} }  |  422 { errors }
```

### 4.2 Initiate payment (`POST /api/v1/orders/:order_id/payments`)

```
Client ──► BaseController#authenticate ──► PaymentsController#create
  ──► PaymentInitiationService#call
        ├─ validate!      order payable, amount == order total, currency match, method allowed
        ├─ check_idempotency!   return existing payment if idempotency_key repeats
        ├─ transaction:
        │     Payment.create!(status: created)
        │     StripeAdapter#initiate_payment  → { status: "processing", provider_reference: "pi_..." }
        │     payment.processing_with_reference(ref)
        │     (dev/test) StripeWebhookSimulator.schedule_webhook(payment, delay: 10s)
        └─ 201 { success, payment: <PaymentSerializer>, metadata }
```

### 4.3 Simulated webhook settles the payment (async)

```
WebhookSimulationJob.perform(payment_id)            # ~10s later
  ──► StripeWebhookSimulator.trigger_webhook        # random outcome (80/20)
        ├─ WebhookEvent.create!(provider_event_id: "evt_...", payload, signature, ...)
        └─ WebhookProcessor.process(event)
              ├─ payment_intent.succeeded  → payment.succeed!   → order.mark_paid! + notify
              ├─ payment_intent.payment_failed → payment.fail_with_reason(...)
              └─ refund.succeeded          → payment.refund!    → order.refund!
  ◄── Turbo Stream broadcast to "merchant_<id>_test_console" (dev/test)
```

Because the simulator creates the event *inside* the same process, the "receive" leg
of a real webhook (HTTP endpoint, signature verification) is replaced by direct
invocation — the processing leg (persist → dedup → exactly-once transition) is real.

## 5. Security model

| Concern | Mechanism |
|---------|-----------|
| API auth | `X-Api-Key` + `X-Api-Secret`; `ApiCredential.authenticate` does BCrypt constant-time comparison; inactive/revoked/expired credentials rejected |
| Tenancy | All API queries scoped to `current_merchant`; `ensure_merchant_active!` rejects suspended merchants |
| Dashboard auth | Devise; inactive users cannot sign in; merchant membership required |
| Credential lifecycle | One-time raw secret shown at creation; 90-day expiry; revocation; reactivation |
| Secrets | `config/credentials.yml.enc` (master key gitignored), `.env` gitignored; secrets never in code |
| Transport | TLS assumed terminated at the edge; not enforced in-app (see assumptions A31) |
| Rate limiting | `rack-attack` declared in Gemfile but **not configured** — a known gap (see README) |
| Authorization | Merchant-scoping is implicit; Pundit declared but **not wired up** — a known gap |

## 6. Reliability & data consistency

1. **Money integrity at the DB level** — NOT NULL, positive-amount, currency-list,
   quantity, and `total = qty × unit` check constraints; the schema is the source of
   truth (see `update_payment_status_constraints` migration).
2. **Idempotent payment initiation** — unique `(order_id, idempotency_key)` index;
   duplicate calls return the original payment; `RecordNotUnique` race handling.
3. **Exactly-once webhook processing** — unique `provider_event_id` + transactional
   mark-processing→process→complete pattern; retries capped at 3 with 5-minute
   backoff; every event persisted for audit/replay.
4. **State machine guards** — illegal transitions (e.g., `succeed` without a
   provider reference) are impossible to express, not just discouraged.
5. **Transactional payment creation** — record + provider call + transition are
   atomic (assessment scope; production moves the provider call out of the DB
   transaction into an outbox/SAGA).
6. **Status timestamps** — `paid_at`, `succeeded_at`, etc. enable metrics and audit.
7. **Partial indexes** — hot paths (pending orders/payments, merchant completed
   sets) are indexed without penalizing writes.

## 7. Testing strategy

| Layer | Files | Focus |
|-------|-------|-------|
| Models | `spec/models/{merchant,user,api_credential,order,order_item,payment,webhook_event}_spec.rb` | Validations, AASM transitions & guards, scopes |
| Requests | `spec/requests/api/v1/orders_spec.rb`, `spec/requests/dashboard_spec.rb` | API auth, order creation payloads, dashboard access |
| Jobs | `spec/jobs/webhook_simulation_job_spec.rb` | Job → simulator pipeline |
| Views / helpers | `spec/views/...`, `spec/helpers/...` | Dashboard rendering, formatters |

## 8. Deployment

- **Image**: production `Dockerfile` (Ruby 3.4.10 slim, jemalloc, non-root `rails`
  user, bootsnap + assets precompiled, Thruster).
- **Entrypoint**: `bin/docker-entrypoint` runs `db:prepare` when booting `rails server`.
- **Dev stack**: `docker-compose.yml` — `db` (PostgreSQL 16, healthchecked) + `web`
  (same image, dev command); optional SolidQueue `worker` service commented out.
- **Prod tooling**: Kamal (`config/deploy.yml`), SolidQueue (`config/queue.yml`,
  production uses a dedicated `queue` database), `config/ci.rb` CI tuning.
- **Quality gates**: `bin/rubocop`, `bin/brakeman`, `bin/bundler-audit`, RSpec.

## 9. Trade-offs & decision log

| Decision | Trade-off |
|----------|-----------|
| Monolith (Rails) | One deployable; explicit service seams (adapters, outbox-ready webhook pipeline) keep a future split viable |
| DB-backed SolidQueue | No Redis to operate; queue traffic shares the DB (fine at assessment scale) |
| AASM state machines | Declarative, guarded transitions vs. raw enum writes — slightly more ceremony, far fewer bugs |
| JSON:API serializer | Stable contract for payments; custom (non-JSON:API) envelopes for orders — pragmatic mix |
| In-process webhook simulation | No HTTP surface to secure/test in the mock; the *processing* pipeline is production-shaped, the *transport* is not |
| Dev/test `:async` jobs | Zero-infra local runs; production SolidQueue keeps durable delivery |
| Mock Stripe adapter always `processing` | Deterministic dev flow; randomness confined to the webhook simulator |
