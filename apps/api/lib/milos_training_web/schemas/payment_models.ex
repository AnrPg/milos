defmodule MilosTrainingWeb.Schemas.PaymentModels do
  @moduledoc "OpenAPI schemas for shared and corporate memberships (ADR-098)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_string %Schema{type: :string, nullable: true}

  def beneficiary_schema do
    %Schema{
      title: "SubscriptionBeneficiary",
      type: :object,
      properties: %{
        id: @uuid,
        subscription_id: @uuid,
        membership_id: @uuid,
        user_id: @uuid,
        nickname: @nullable_string,
        is_minor: %Schema{type: :boolean},
        removed_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :subscription_id, :user_id, :is_minor]
    }
  end

  def client_schema do
    %Schema{
      title: "CorporateClient",
      type: :object,
      properties: %{
        id: @uuid,
        membership_package_id: @uuid,
        package_name: @nullable_string,
        company_name: %Schema{type: :string},
        billing_email: @nullable_string,
        contact_name: @nullable_string,
        enrollment_code: %Schema{type: :string},
        enrollment: %Schema{type: :string, enum: ["invite_code", "email_domain"]},
        enrollment_domain: @nullable_string,
        seats: %Schema{type: :integer, nullable: true},
        seat_billing: %Schema{type: :string, enum: ["agreed", "used"]},
        active_seats: %Schema{type: :integer},
        payment_terms_days: %Schema{type: :integer},
        auto_invoice: %Schema{type: :boolean},
        status: %Schema{type: :string, enum: ["active", "archived"]}
      },
      required: [
        :id,
        :membership_package_id,
        :company_name,
        :enrollment_code,
        :active_seats,
        :status
      ]
    }
  end

  def invoice_schema do
    %Schema{
      title: "CorporateInvoice",
      type: :object,
      properties: %{
        id: @uuid,
        corporate_client_id: @uuid,
        period_start: %Schema{type: :string, format: :date},
        period_end: %Schema{type: :string, format: :date},
        seat_billing: %Schema{type: :string},
        seats_billed: %Schema{type: :integer},
        unit_price_cents: %Schema{type: :integer},
        total_cents: %Schema{type: :integer},
        status: %Schema{type: :string, enum: ["issued", "overdue", "paid", "void"]},
        invoice_number: @nullable_string,
        issued_on: %Schema{type: :string, format: :date},
        due_on: %Schema{type: :string, format: :date},
        paid_on: %Schema{type: :string, format: :date, nullable: true},
        paid_cents: %Schema{type: :integer},
        balance_cents: %Schema{type: :integer},
        last_reminded_on: %Schema{type: :string, format: :date, nullable: true},
        reminder_count: %Schema{type: :integer},
        payments: %Schema{type: :array, items: payment_schema()}
      },
      required: [
        :id,
        :period_start,
        :period_end,
        :seats_billed,
        :total_cents,
        :status,
        :due_on,
        :paid_cents,
        :balance_cents,
        :payments
      ]
    }
  end

  def invoice_document_schema do
    %Schema{
      invoice_schema()
      | title: "CorporateInvoiceDocument",
        properties:
          Map.merge(invoice_schema().properties, %{
            client: client_schema(),
            issuer: %Schema{
              type: :object,
              properties: %{name: %Schema{type: :string}},
              required: [:name]
            }
          }),
        required: invoice_schema().required ++ [:client, :issuer]
    }
  end

  def payment_schema do
    %Schema{
      title: "CorporatePayment",
      type: :object,
      properties: %{
        id: @uuid,
        amount_cents: %Schema{type: :integer},
        payment_method: %Schema{type: :string, enum: payment_methods()},
        paid_on: %Schema{type: :string, format: :date},
        reference: @nullable_string,
        notes: @nullable_string,
        recorded_by_id: %Schema{type: :string, format: :uuid, nullable: true},
        reversed_at: %Schema{type: :string, format: :"date-time", nullable: true},
        reversal_reason: @nullable_string
      },
      required: [:id, :amount_cents, :payment_method, :paid_on]
    }
  end

  def payment_request_schema do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        amount_cents: %Schema{type: :integer, minimum: 1},
        payment_method: %Schema{type: :string, enum: payment_methods()},
        paid_on: %Schema{type: :string, format: :date, nullable: true},
        reference: %Schema{type: :string, maxLength: 120, nullable: true},
        notes: %Schema{type: :string, maxLength: 1000, nullable: true}
      },
      required: [:amount_cents, :payment_method]
    }
  end

  defp payment_methods, do: ["cash", "bank_transfer", "card_manual", "other"]

  def seat_schema do
    %Schema{
      title: "CorporateSeat",
      type: :object,
      additionalProperties: true,
      properties: %{
        id: @uuid,
        user_id: @uuid,
        nickname: @nullable_string,
        status: %Schema{type: :string},
        starts_on: %Schema{type: :string, format: :date, nullable: true},
        ends_on: %Schema{type: :string, format: :date, nullable: true}
      },
      required: [:id, :user_id, :status]
    }
  end

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def optional_body(schema),
    do: %RequestBody{
      required: false,
      content: %{"application/json" => %MediaType{schema: schema}}
    }

  def wrap(key, schema), do: %Schema{type: :object, properties: %{key => schema}, required: [key]}
  def list(key, schema), do: wrap(key, %Schema{type: :array, items: schema})
end
