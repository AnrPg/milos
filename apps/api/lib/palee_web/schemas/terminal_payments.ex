defmodule PaleeWeb.Schemas.TerminalPayments do
  @moduledoc "OpenAPI schemas of Tap to Pay at the desk (ADR-249, ADR-264)."

  alias OpenApiSpex.Schema
  alias PaleeWeb.Schemas.Payments, as: P

  @text %Schema{type: :string, nullable: true}

  @availability_reasons ~w(no_viva stripe_only provider_without_terminal account_not_ready)

  def availability do
    %Schema{
      type: :object,
      properties: %{
        available: %Schema{type: :boolean},
        reason: %Schema{
          type: :string,
          enum: @availability_reasons,
          nullable: true,
          description:
            "Why not (ADR-272): no payment account, Stripe (no terminal app in Palee), " <>
              "another provider without one, or an account that is not active. Whether the " <>
              "phone has the terminal app is known on the phone only."
        },
        provider: %Schema{type: :string, nullable: true}
      },
      required: [:available, :provider, :reason]
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
            description: "The member; none for a walk-in (a shop order or a free sale, ADR-264)."
        },
        amount_cents: %Schema{type: :integer, minimum: 1, maximum: 10_000_000},
        description: %Schema{type: :string, maxLength: 120, nullable: true},
        charge_category: %Schema{
          type: :string,
          enum: ["product", "personal_training", "event", "other"],
          nullable: true
        },
        idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 200},
        started_on: %Schema{
          type: :string,
          enum: ["phone", "desk"],
          nullable: true,
          description:
            "Where the payment was started (ADR-272), for its tip: on the staff member's " <>
              "phone (default) or at the desk."
        }
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
            },
            document: %Schema{receipt() | nullable: true},
            fiscal_document_id: %{P.uuid() | nullable: true},
            started_by_id: %{P.uuid() | nullable: true},
            started_on: %Schema{type: :string, enum: ["phone", "desk"]},
            tip_attribution: %Schema{
              type: :string,
              enum: ["started_payment", "sole_front_desk", "front_desk_role"],
              nullable: true,
              description:
                "Whose tip it is (ADR-272): who started the payment on their phone, the box's " <>
                  "only front desk person, or the front desk role unpersonalised."
            },
            tip_recipient_user_id: %{P.uuid() | nullable: true},
            tip_recipient_role: %Schema{type: :string, enum: ["front_desk"], nullable: true}
          }),
        required:
          Enum.sort(
            [
              :document,
              :reference,
              :started_on,
              :surcharge_cents,
              :tip_attribution,
              :tip_cents,
              :tip_recipient_user_id
            ] ++ intent.required
          )
    }
  end

  @doc "ADR-272: the fiscal document a Tap to Pay payment issued."
  def receipt do
    %Schema{
      type: :object,
      properties: %{
        id: P.uuid(),
        kind: %Schema{type: :string, enum: ["receipt", "invoice"]},
        number: %Schema{type: :string},
        gross_cents: %Schema{type: :integer},
        currency: %Schema{type: :string},
        issued_at: %Schema{type: :string, format: :"date-time", nullable: true},
        authority: %Schema{type: :string, nullable: true},
        transmission_status: %Schema{
          type: :string,
          enum: ["pending", "sending", "accepted", "rejected", "failed"],
          nullable: true,
          description: "Its transmission to the tax authority; none where the country has none."
        },
        receipt_url: %Schema{
          type: :string,
          nullable: true,
          description:
            "A walk-in's receipt as an open, signed link (90 days) for the QR on the phone."
        }
      },
      required: [
        :authority,
        :currency,
        :gross_cents,
        :id,
        :kind,
        :number,
        :receipt_url,
        :transmission_status
      ]
    }
  end

  @doc "ADR-272: «Αποστολή με email» of the payment's receipt."
  def receipt_email_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 120},
        to: %Schema{
          type: :string,
          maxLength: 254,
          nullable: true,
          description: "Required for a walk-in; a member's account email when left out."
        },
        language: %Schema{type: :string, enum: ["el", "en", "de", "fr", "it", "nl", "es"]}
      },
      required: [:idempotency_key]
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

  # ── ADR-272: desk buyers and tips ──────────────────────────────────────

  @relations ~w(member athlete guest none)

  def desk_person do
    %Schema{
      type: :object,
      properties: %{
        user_id: P.uuid(),
        name: %Schema{type: :string, nullable: true},
        avatar_url: %Schema{type: :string, nullable: true},
        relation: %Schema{
          type: :string,
          enum: @relations,
          description: "Box member, athlete, guest of the box, or not in the box yet."
        },
        checked_in_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:avatar_url, :checked_in_at, :name, :relation, :user_id]
    }
  end

  def desk_people do
    %Schema{
      type: :object,
      properties: %{people: %Schema{type: :array, items: desk_person()}},
      required: [:people]
    }
  end

  def desk_options do
    money = fn props, required ->
      %Schema{type: :object, properties: props, required: Enum.sort(required)}
    end

    package =
      money.(
        %{
          id: P.uuid(),
          name: %Schema{type: :string},
          price_cents: %Schema{type: :integer},
          currency: %Schema{type: :string}
        },
        [:currency, :id, :name, :price_cents]
      )

    %Schema{
      type: :object,
      properties: %{
        options: %Schema{
          type: :object,
          properties: %{
            user_id: %{P.uuid() | nullable: true},
            relation: %Schema{type: :string, enum: ["walk_in" | @relations]},
            invoices: %Schema{
              type: :array,
              items:
                money.(
                  %{
                    id: P.uuid(),
                    number: %Schema{type: :string, nullable: true},
                    description: %Schema{type: :string, nullable: true},
                    balance_due_cents: %Schema{type: :integer},
                    currency: %Schema{type: :string}
                  },
                  [:balance_due_cents, :currency, :description, :id, :number]
                )
            },
            renewal: %Schema{
              package
              | nullable: true,
                properties:
                  Map.put(package.properties, :ends_on, %Schema{
                    type: :string,
                    format: :date,
                    nullable: true
                  })
            },
            packages: %Schema{type: :array, items: package},
            shop_orders: %Schema{
              type: :array,
              items:
                money.(
                  %{
                    id: P.uuid(),
                    number: %Schema{type: :integer},
                    total_cents: %Schema{type: :integer},
                    currency: %Schema{type: :string},
                    customer_name: %Schema{type: :string, nullable: true},
                    summary: %Schema{type: :string}
                  },
                  [:currency, :customer_name, :id, :number, :summary, :total_cents]
                )
            }
          },
          required: [:invoices, :packages, :relation, :renewal, :shop_orders, :user_id]
        }
      },
      required: [:options]
    }
  end

  def guest_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      description: "A found person (`user_id`), or a walk-in's `name` and `email`.",
      properties: %{
        user_id: %{P.uuid() | nullable: true},
        name: %Schema{type: :string, maxLength: 120, nullable: true},
        email: %Schema{type: :string, maxLength: 254, nullable: true}
      }
    }
  end

  def guest do
    %Schema{
      type: :object,
      properties: %{
        person: desk_person(),
        created_profile: %Schema{
          type: :boolean,
          description: "A new, held profile was made for a walk-in (ADR-254)."
        },
        added: %Schema{type: :boolean, description: "The person became a guest of the box now."}
      },
      required: [:added, :created_profile, :person]
    }
  end

  def tips do
    %Schema{
      type: :object,
      properties: %{
        from: %Schema{type: :string, format: :date},
        to: %Schema{type: :string, format: :date},
        currency: %Schema{type: :string, nullable: true},
        total_cents: %Schema{type: :integer},
        rows: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              kind: %Schema{type: :string, enum: ["person", "front_desk_role", "unattributed"]},
              user_id: %{P.uuid() | nullable: true},
              name: %Schema{type: :string, nullable: true},
              tip_cents: %Schema{type: :integer},
              payments: %Schema{type: :integer}
            },
            required: [:kind, :name, :payments, :tip_cents, :user_id]
          }
        }
      },
      required: [:currency, :from, :rows, :to, :total_cents]
    }
  end
end
