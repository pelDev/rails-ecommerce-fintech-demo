class PaymentProvider::BaseAdapter
    attr_reader :payment, :params

    def initialize(payment, params = {})
      @payment = payment
      @params = params
    end

    def initiate_payment
      raise NotImplementedError, "Subclasses must implement initiate_payment"
    end

    protected

    def success_response(reference, additional_data = {})
      {
        status: 'succeeded',
        provider_reference: reference,
        **additional_data
      }
    end

    def pending_response(reference, additional_data = {})
      {
        status: 'pending',
        provider_reference: reference,
        **additional_data
      }
    end

    def processing_response(reference, additional_data = {})
      {
        status: 'processing',
        provider_reference: reference,
        **additional_data
      }
    end

    def failure_response(reason, additional_data = {})
      {
        status: 'failed',
        failure_reason: reason,
        **additional_data
      }
    end
end
