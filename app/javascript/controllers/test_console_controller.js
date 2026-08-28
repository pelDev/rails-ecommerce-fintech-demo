import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "apiKey",
    "apiSecret",
    "currency",
    "extRef",
    "itemName",
    "itemQty",
    "itemPrice",
    "itemsContainer",
    "orderConsole",
    "paymentConsole",
    "orderResponse",
    "paymentAmount",
    "paymentCurrency",
    "paymentMethod",
    "idempotencyKey",
    "paymentResponse",
  ];

  connect() {
    this.orderItems = [];
    this.currentOrder = null;
    this.addOrderItem();
  }

  // --- Dynamic Order Items ---

  addOrderItem() {
    const id = Date.now();
    this.orderItems.push({
      id,
      product_name: "Test Item",
      quantity: 1,
      unit_price_cents: 2500,
    });
    this.renderItems();
  }

  removeOrderItem(event) {
    const id = parseInt(event.currentTarget.dataset.id);
    this.orderItems = this.orderItems.filter((item) => item.id !== id);
    this.renderItems();
  }

  renderItems() {
    this.itemsContainerTarget.innerHTML = this.orderItems
      .map(
        (item, index) => `
      <div class="flex gap-2 items-center mb-2" data-item-id="${item.id}">
        <input type="text" placeholder="Product Name" value="${item.product_name}" 
          class="item-name flex-1 text-xs p-2 border rounded-md" 
          oninput="this.dispatchEvent(new CustomEvent('item-change', {bubbles: true}))">
        
        <input type="number" placeholder="Qty" value="${item.quantity}" 
          class="item-qty w-16 text-xs p-2 border rounded-md" 
          oninput="this.dispatchEvent(new CustomEvent('item-change', {bubbles: true}))">
        
        <input type="number" placeholder="Price (Cents)" value="${item.unit_price_cents}" 
          class="item-price w-28 text-xs p-2 border rounded-md" 
          oninput="this.dispatchEvent(new CustomEvent('item-change', {bubbles: true}))">
        
        ${
          this.orderItems.length > 1
            ? `
          <button type="button" data-action="click->test-console#removeOrderItem" data-id="${item.id}" 
            class="text-red-500 hover:text-red-700 text-xs px-2 py-1">✕</button>
        `
            : ""
        }
      </div>
    `,
      )
      .join("");
  }

  // --- API Action 1: Create Order ---

  async createOrder(e) {
    e.preventDefault();

    // Scrape dynamic items from DOM
    const items = Array.from(this.itemsContainerTarget.children).map((row) => ({
      product_name: row.querySelector(".item-name").value,
      quantity: parseInt(row.querySelector(".item-qty").value || 1),
      unit_price_cents: parseInt(row.querySelector(".item-price").value || 0),
    }));

    const payload = {
      currency: this.currencyTarget.value,
      external_reference:
        this.extRefTarget.value || `REF-${Math.floor(Math.random() * 1000000)}`,
      order_items_attributes: items,
    };

    this.orderResponseTarget.textContent = "Creating order via API...";

    try {
      const response = await fetch("/api/v1/orders", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Api-Key": this.apiKeyTarget.value,
          "X-Api-Secret": this.apiSecretTarget.value,
        },
        body: JSON.stringify({ order: payload }),
      });

      const data = await response.json();
      this.orderResponseTarget.textContent = JSON.stringify(data, null, 2);

      if (data.success && data.order) {
        this.currentOrder = data.order;
        this.setupPaymentSection(data.order);
      }
    } catch (error) {
      this.orderResponseTarget.textContent = JSON.stringify(
        { error: error.message },
        null,
        2,
      );
    }
  }

  setupPaymentSection(order) {
    this.paymentConsoleTarget.classList.remove("hidden");
    this.paymentAmountTarget.value = order.amount_cents;
    this.paymentCurrencyTarget.value = order.currency;
    this.idempotencyKeyTarget.value = `IDEM-${Date.now()}`;
  }

  // --- API Action 2: Initiate Payment ---

  async initiatePayment(e) {
    e.preventDefault();
    if (!this.currentOrder) return;

    const payload = {
      amount: parseInt(this.paymentAmountTarget.value),
      currency: this.paymentCurrencyTarget.value,
      payment_method: this.paymentMethodTarget.value,
      idempotency_key: this.idempotencyKeyTarget.value,
      provider_params: {},
      metadata: { simulated_by: "TestConsole" },
    };

    this.paymentResponseTarget.textContent = "Initiating payment...";

    try {
      const response = await fetch(
        `/api/v1/orders/${this.currentOrder.id}/payments`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Api-Key": this.apiKeyTarget.value,
            "X-Api-Secret": this.apiSecretTarget.value,
          },
          body: JSON.stringify(payload),
        },
      );

      const data = await response.json();
      this.paymentResponseTarget.textContent = JSON.stringify(data, null, 2);
    } catch (error) {
      this.paymentResponseTarget.textContent = JSON.stringify(
        { error: error.message },
        null,
        2,
      );
    }
  }
}
