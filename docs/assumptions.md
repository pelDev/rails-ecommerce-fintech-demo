# Assumptions

This document records the explicit assumptions the platform is built on. Where an
assumption is a deliberate scope cut, a mock, or a workaround, it is called out so
you (reviewer) can distinguish *design decisions* from *shortcuts*.

Each entry follows the shape: **We assume X — because Y. If Z happens in
production, we would do W.**

---

## 1. Product scope

| # | Assumption | Rationale / production gap |
|---|------------|----------------------------|
| A1 | **No inventory management.** Orders do not reserve, decrement, or check stock. | Out of scope for a payment platform; inventory lives in the merchant's own systems. Production: expose stock hooks/events, never block payment on stock. |
| A2 | **Order status is tracked beyond payment.** An order has its own lifecycle (`pending → paid → shipped → delivered`, plus `cancelled`, `refunded`, `expired`) that is *driven by but distinct from* payment status. | A B2B order is a fulfillment document, not just a payment. A payment succeeding moves the order to `paid`; shipping/delivery are merchant actions. |
| A3 | **A dashboard exists for merchants** to view orders and payments, generate API credentials, and exercise a Test Console. | Required by the brief. Production: multi-role RBAC, audit log, pagination/filtering. |
| A4 | **The payment provider is a mock.** No real money movement, no real provider accounts, no real network calls. | Required by the brief ("you will build a mock payment provider"). Production: real provider sandboxes, then live keys, with the adapter seam unchanged. |

## 2. Money & amounts

| # | Assumption | Rationale / production gap |
|---|------------|----------------------------|
| A5 | **All amounts are integer minor units (cents), stored and transported as integers.** | Avoids float rounding errors in financial data. Enforced by `amount_cents`/`unit_price_cents`/`total_price_cents` columns, all `NOT NULL`, and DB check constraints `> 0`. |
| A6 | **Order totals are computed server-side** from line items (`quantity * unit_price_cents`); the client cannot set the total. | A merchant must never trust client-supplied totals. Enforced in `OrderItem` (`calculate_total_price`, `total_price_matches_quantity_price`) and at the DB level (`order_items_total_price_calculation_check`). |
| A7 | **A payment amount must equal the order total exactly.** | Partial payments are out of scope. Enforced by `Payment#amount_matches_order_total` and `PaymentInitiationService` (`AMOUNT_MISMATCH`). |
| A8 | **One currency per order and per payment, chosen from a fixed 20-currency ISO-4217 list** (USD, EUR, GBP, JPY, CAD, AUD, CHF, CNY, HKD, NZD, SEK, KRW, SGD, NOK, MXN, INR, BRL, ZAR, TRY, RUB). | A single-currency order model. Enforced in models and by DB check constraints (`*_currency_valid_check`). **No FX conversion or multi-currency settlement** — production would add an FX layer and per-currency ledger. |
| A9 | **No partial captures, no refunds at the provider level, no chargebacks, no disputes.** A "refund" is a full payment refund and is simulated. | Out of scope. Production: refunds/chargebacks via provider APIs, reconciliation. |

## 3. Orders

| # | Assumption | Rationale / production gap |
|---|------------|----------------------------|
| A10 | **`external_reference` is optional but unique.** The form enforces uniqueness per merchant; the DB enforces a *global* unique index on `external_reference`. | We assume merchants supply globally unique references (e.g., their own order numbers prefixed per tenant). If collisions were observed, the DB constraint would be relaxed to `(merchant_id, external_reference)`. |
| A11 | **Orders expire after 24 hours while still `pending`** (`Order#can_expire?`, `Order.expire_pending_orders!`). | Prevents unbounded pending orders. Production: run the expiry sweep on a schedule (SolidQueue recurring job / cron) rather than on demand. |
| A12 | **An order is payable only while `pending`, not expired/cancelled/refunded, and not already fully paid.** | `PaymentInitiationService#order_payable?`. |
| A13 | **Overpayment is detectable but not prevented** (`Order#payment_status` can return `"overpaid"`). | We assume well-behaved clients; production would reject or reconcile overpayment. |

## 4. Payments

| # | Assumption | Rationale / production gap |
|---|------------|----------------------------|
| A14 | **A payment follows `created → pending → processing → succeeded | failed`, with `refunded` from `succeeded`.** All transitions are guarded AASM transitions; direct status writes are prevented by the state machine. | Deterministic lifecycle; DB check `payments_status_valid_check` mirrors the enum. |
| A15 | **`provider_reference` is required for `succeeded` and unique across payments** (DB unique index + `payments_provider_reference_check`). | Every successful payment must be traceable to a provider object. |
| A16 | **`failure_reason` is required for `failed` and must be absent otherwise** (DB check `payments_failure_reason_check`). | Enforces consistent failure records. |
| A17 | **Idempotency is client-optional: a caller may pass `idempotency_key`, unique per order** (DB unique index on `(order_id, idempotency_key)`). Duplicate calls return the *existing* payment instead of creating a new one; races are caught via `RecordNotUnique` and resolved. | At-least-once client retries must not double-charge. Production: require idempotency keys for all mutations and validate format/length. |
| A18 | **Automatic retry is limited to 3 attempts** (`Payment#can_retry?`). | Bounded retry prevents runaway provider calls. Note: the `retry` event references a `PaymentProcessorJob` that is not implemented — see [Known gaps](../README.md#known-gaps). |
| A19 | **Status timestamps are maintained** (`pending_at`, `processing_at`, `succeeded_at`, `failed_at`, `refunded_at`) and exposed via the serializer. | Enables processing-time metrics (`Payment#processing_time_in_seconds`). |
| A20 | **A payment success is what marks an order `paid`**, via `Payment#succeed` → `order.mark_paid!` (guarded by `payments.successful.exists?`). | Payment and order statuses are coupled only at this one point by design. |

## 5. Payment provider (mock)

| # | Assumption | Rationale / production gap |
|---|------------|----------------------------|
| A21 | **Provider integration goes through a single seam**: `PaymentProvider::BaseAdapter` with `initiate_payment` returning a normalized hash (`status: succeeded|pending|processing|failed`, `provider_reference`, `failure_reason`). | Swapping the mock for a real provider (Stripe/PayPal/…) is a change inside one adapter, not across the app. |
| A22 | **The Stripe adapter currently returns `processing` for every initiation** (the random-outcome line is commented out). Final outcome is decided by the simulated webhook. | Mirrors real async providers where initiation ≠ settlement. Production: real `payment_intent` creation + webhook-driven final state. |
| A23 | **All payment methods route to the Stripe adapter for now** (`PaymentInitiationService#provider_adapter_for` has the dispatch table commented out). | Placeholder — see [Placeholders & mocks](../README.md#placeholders-mocks-and-workarounds). |
| A24 | **The simulated webhook outcome is random: ~80% `succeeded`, ~20% `failed`**, delivered ~10s after initiation via a background job. | Gives the Test Console a realistic async flow. Production: provider-real probabilities are irrelevant — the mechanism is what matters. |
| A25 | **Allowed payment methods**: `card`, `bank_transfer`, `paypal`, `stripe`, `square` (service) / `cash` additionally accepted by the model. | Simple allowlist. Production: method-specific validation (3DS, SCA, scheme rules). |

## 6. Webhooks (simulated)

| # | Assumption | Rationale / production gap |
|---|------------|----------------------------|
| A26 | **No real webhooks are sent or received over HTTP.** A simulated event is created in-process and processed through the same `WebhookProcessor` pipeline a real HTTP delivery would use. | The brief allows a mock provider. Production: a signed `POST /webhooks/:provider` endpoint (HMAC verification), an outbox + dispatcher for guaranteed delivery, retries with exponential backoff, and a DLQ. |
| A27 | **Webhook delivery semantics are at-least-once; consumers must be idempotent.** | Dedup is enforced by the unique `provider_event_id` on `webhook_events` (`WebhookEvent.find_or_process` returns the existing record on `RecordNotUnique`). |
| A28 | **Every received/simulated event is persisted** with payload, signature, source IP, user agent, and processing status (`pending → processing → completed | failed`). | Auditability and replay/retry support. |
| A29 | **Webhook processing is exactly-once per event record** via a transactional "mark processing → process → mark completed/failed" pattern (`WebhookEvent#process!`), with up to 3 retries and a 5-minute backoff. | Protects against double-crediting a payment. Note: the retry enqueues a `WebhookEventJob` that is not implemented — see [Known gaps](../README.md#known-gaps). |
| A30 | **Signatures are placeholders** (`'simulated_signature'`); no cryptographic verification happens because events never cross a network boundary. | Production: verify provider signature before trusting the payload. |

## 7. Security & tenancy

| # | Assumption | Rationale / production gap |
|---|------------|----------------------------|
| A31 | **API authentication is API-key + secret over HTTPS headers** (`X-Api-Key`, `X-Api-Secret`), BCrypt-hashed secrets (cost 12), constant-time comparison, per-credential `active` flag, revocation, and a 90-day expiry. | Simple, testable model. Production: HMAC request signing, key rotation workflows, per-IP allowlists. TLS is assumed to be terminated at the edge — the app does not enforce it. |
| A32 | **All API data access is merchant-scoped** (orders/payments are queried through `current_merchant`). | Multi-tenant isolation at the query level. |
| A33 | **Dashboard auth is Devise** (registerable, recoverable, rememberable, trackable, timeoutable) with roles `user | admin | super_admin` and merchant membership required. | Production: proper RBAC policies (Pundit is declared in the Gemfile but **not yet wired up**), session hardening, MFA. |
| A34 | **Suspended/inactive merchants are rejected by the API** (`ensure_merchant_active!`) and inactive users cannot authenticate (`active_for_authentication?`). | Simple suspension model. |

## 8. Data integrity & consistency

| # | Assumption | Rationale / production gap |
|---|------------|----------------------------|
| A35 | **Database constraints are the last line of defense**: NOT NULL on all money columns, positive-amount checks, currency list checks, status-enum checks, `total = quantity * unit_price` check, conditional checks for `provider_reference`/`failure_reason`. | Model validations can be bypassed; constraints cannot. |
| A36 | **Payment initiation is transactional**: payment record creation + provider call + state transition happen in one DB transaction; failures roll back cleanly. | `PaymentInitiationService#call`. Production: provider calls must be moved *outside* the DB transaction (outbox / SAGA) to avoid long-held locks. |
| A37 | **Timestamps are UTC** (Rails default) and all times are `Time.current`. | Avoids DST bugs. |
| A38 | **Partial indexes exist for hot query patterns** (pending orders/payments by creation time, completed by merchant, etc.). | Query performance without bloating every write. |

## 9. Background processing & deployment

| # | Assumption | Rationale / production gap |
|---|------------|----------------------------|
| A39 | **Jobs run on the in-process `:async` adapter in development/test and SolidQueue (DB-backed) in production.** | No external infrastructure for local dev; a real durable queue in production. Production: SolidQueue needs a dedicated worker process (see `docker-compose.yml` commented `worker` service), retry policies, and DLQ. |
| A40 | **Deployment targets a single Rails app + single PostgreSQL instance** (Docker/Kamal). | Assessment scope. Production: read replicas, connection pooling, horizontal workers, sharding per merchant. |
| A41 | **The webhook `notify_merchant` path uses Turbo Streams broadcasts in dev/test** (Test Console real-time feed) and is stubbed to a comment in production. | Workaround — see [Placeholders & mocks](../README.md#placeholders-mocks-and-workarounds). |

## 10. Testing

| # | Assumption | Rationale / production gap |
|---|------------|----------------------------|
| A42 | **RSpec covers models (validations, AASM transitions, scopes), key request flows (API orders, dashboard), jobs, and views.** | Matches the current `spec/` tree. Production: property tests for money math, contract tests for provider adapters, load tests. |
| A43 | **`update_payment_status_constraints` migration is authoritative for payment status rules**; the schema is the source of truth for constraints. | Schema (`db/schema.rb`) should be regenerated with `bin/rails db:migrate` — never hand-edited. |
