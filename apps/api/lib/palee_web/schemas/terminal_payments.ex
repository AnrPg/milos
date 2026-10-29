defmodule PaleeWeb.Schemas.TerminalPayments do
  @moduledoc "OpenAPI schemas of Tap to Pay at the desk (ADR-249, ADR-264)."

  alias OpenApiSpex.Schema
  alias PaleeWeb.Schemas.Payments, as: P

  @text %Schema{type: :string, nullable: true}

  def availability do
    %Schema{
      type: :object,
      properties: %{available: %Schema{type: :boolean}},
      required: [:available]
    }
  end

  def start_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        purpose: %Schema{
          type: :string,
          enum: ~w(finance_invoice membership_package shop_order free_sale)
        },
        purpose_id: %{P.uuid() | nullable: true},
        user_id: %{
          P.uuid()
          | nullable: true,
            description:
              "The member; none for a walk-in (a shop order or a free sale, ADR-264)."
        },
        amount_cents: %Schema{type: :integer, minimum: 1, maximum: 10_000_000},
        description: %Schema{type: :string, maxLength: 120, nullable: true},
        charge_category: %Schema{
          type: :string,
          enum: ["product", "personal_training", "event", "other"],
          nullable: true
        },
        idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 200}
      },
      required: [:amount_cents, :idempotency_key, :purpose]
    }
  end

  def app_request do
    %Schema{
      type: :object,
      nullable: true,
      description:
        "What the phone hands to the provider's terminal app (Viva: an Android intent or " <>
          "iOS URL); absent once the request may no longer be launched.",
      properties: %{
        scheme: %Schema{type: :string},
        params: %Schema{type: :object, additionalProperties: %Schema{type: :string}},
        url: %Schema{type: :string}
      },
      required: [:params, :scheme, :url]
    }
  end

  def terminal_payment do
    intent = P.intent()

    %Schema{
      intent
      | properties:
          Map.merge(intent.properties, %{
            reference: %Schema{
              type: :string,
              description: "The signed reference the terminal app keeps (clientTransactionId)."
            },
            failure_message: @text,
            app_request: app_request(),
            tip_cents: %Schema{
              type: :integer,
              minimum: 0,
              description:
                "Tip the provider confirmed on top of the amount (ADR-264): the staff's, " <>
                  "not revenue of the sale."
            },
            surcharge_cents: %Schema{
              type: :integer,
              minimum: 0,
              description:
                "Card surcharge the provider added on top of the amount (ADR-264): part of " <>
                  "the sale's price, on its receipt."
            }
          }),
        required: Enum.sort([:reference, :surcharge_cents, :tip_cents | intent.required])
    }
  end

  def result_body do
    %Schema{
      type: :object,
      description: "What the terminal app returned on the callback, as the phone parsed it.",
      properties: %{
        reference: %Schema{type: :string, maxLength: 300},
        status: %Schema{type: :string, maxLength: 20},
        transaction_id: %Schema{type: :string, maxLength: 200, nullable: true},
        message: %Schema{type: :string, maxLength: 500, nullable: true}
      },
      required: [:reference, :status]
    }
  end

  def sandbox_body do
    %Schema{
      type: :object,
      properties: %{
        outcome: %Schema{type: :string, enum: ["succeeded", "failed", "cancelled"]},
        tip_cents: %Schema{type: :integer, minimum: 0, nullable: true},
        surcharge_cents: %Schema{type: :integer, minimum: 0, nullable: true},
        amount_cents: %Schema{
          type: :integer,
          minimum: 1,
          nullable: true,
          description: "What the card paid in all, to try a mismatch (default: amount + extras)."
        }
      },
      required: [:outcome]
    }
  end
end
