# Flow

This showcases your the Test Console UI Operates

┌─────────────────────────────────────────────────────────┐
│              Test Console UI (Stimulus)                 │
└──────────┬────────────────────────────────────┬─────────┘
           │ 1. POST /api/v1/orders             │ 2. POST /api/v1/orders/:id/payments
           │    Header: X-Api-Key/Secret        │    Header: X-Api-Key/Secret
           ▼                                    ▼
┌─────────────────────────┐          ┌──────────────────────────────────┐
│  OrderCreationForm      │          │ PaymentInitiationService         │
├─────────────────────────┤          ├──────────────────────────────────┤
│ • Validates line items  │          │ • Accepts order & payment_params │
│ • Calculates total      │          │ • Processes payment method       │
│ • Returns JSON payload  │          │ • Returns PaymentSerializer      │
└─────────────────────────┘          └──────────────────────────────────┘