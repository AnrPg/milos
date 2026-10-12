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
        status: %Schema{type: :string, enum: ["issued", "paid", "void"]},
        issued_on: %Schema{type: :string, format: :date},
        paid_on: %Schema{type: :string, format: :date, nullable: true}
      },
      required: [:id, :period_start, :period_end, :seats_billed, :total_cents, :status]
    }
  end

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
