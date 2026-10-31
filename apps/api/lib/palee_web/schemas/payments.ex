defmodule PaleeWeb.Schemas.Payments do
  @moduledoc "OpenAPI schemas of online payments (ADR-246/247)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @time %Schema{type: :string, format: :"date-time", nullable: true}
  @text %Schema{type: :string, nullable: true}
  @int %Schema{type: :integer}

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def one(key, schema), do: %Schema{type: :object, properties: %{key => schema}, required: [key]}

  def account do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        provider: %Schema{type: :string, enum: ["sandbox", "viva", "stripe"]},
        environment: %Schema{type: :string, enum: ["test", "live"]},
        status: %Schema{type: :string},
        settings: %Schema{type: :object, additionalProperties: %Schema{type: :string}},
        credentials_set: %Schema{type: :array, items: %Schema{type: :string}},
        last_error: @text,
        checked_at: @time,
        updated_at: @time,
        webhook_url: %Schema{type: :string},
        options: options(),
        connection: %Schema{type: :string, enum: ["keys", "platform"]},
        packages_notice: %Schema{
          type: :object,
          nullable: true,
          description:
            "ADR-271: connecting put `count` paid packages on sale online; shown until " <>
              "the owner closes it",
          properties: %{count: @int, opened_at: %Schema{type: :string, format: :"date-time"}},
          required: [:count, :opened_at]
        }
      },
      required: [
        :connection,
        :credentials_set,
        :environment,
        :id,
        :options,
        :packages_notice,
        :provider,
        :settings,
        :status,
        :webhook_url
      ]
    }
  end

  @doc "ADR-260: what members pay online and who hears about failed charges."
  def options do
    flag = %Schema{type: :boolean}

    purposes = %Schema{
      type: :object,
      properties: %{
        packages: flag,
        autopay: flag,
        drop_in: flag,
        shop: flag,
        personal_training: flag
      },
      required: [:autopay, :drop_in, :packages, :personal_training, :shop]
    }

    %Schema{
      type: :object,
      properties: %{purposes: purposes, notify_member: flag, notify_staff: flag},
      required: [:notify_member, :notify_staff, :purposes]
    }
  end

  def connect_body do
    %Schema{
      type: :object,
      properties: %{
        provider: %Schema{type: :string, enum: ["viva", "stripe"]},
        environment: %Schema{type: :string, enum: ["test", "live"], default: "live"}
      },
      required: [:provider]
    }
  end

  def connect_start do
    %Schema{type: :object, properties: %{url: %Schema{type: :string}}, required: [:url]}
  end

  def options_body do
    flag = %Schema{type: :boolean}

    %Schema{
      type: :object,
      properties: %{
        purposes: %Schema{
          type: :object,
          properties: %{
            packages: flag,
            autopay: flag,
            drop_in: flag,
            shop: flag,
            personal_training: flag
          }
        },
        notify_member: flag,
        notify_staff: flag
      }
    }
  end

  def account_status do
    %Schema{
      type: :object,
      properties: %{
        account: %{account() | nullable: true},
        providers: %Schema{type: :array, items: %Schema{type: :string}},
        environments: %Schema{type: :array, items: %Schema{type: :string}},
        connect_providers: %Schema{
          type: :object,
          description: "Providers that connect with one button, per environment (ADR-261)",
          additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}
        },
        online_sales: %Schema{
          type: :object,
          description:
            "ADR-271: of the active paid packages (`packages`), how many are sold online",
          properties: %{sold_online: @int, packages: @int},
          required: [:packages, :sold_online]
        }
      },
      required: [:account, :connect_providers, :environments, :online_sales, :providers]
    }
  end

  def account_body do
    secret = %Schema{type: :string, maxLength: 500}

    %Schema{
      type: :object,
      properties: %{
        provider: %Schema{type: :string, enum: ["sandbox", "viva", "stripe"]},
        environment: %Schema{type: :string, enum: ["test", "live"]},
        credentials: %Schema{
          type: :object,
          properties: %{
            client_id: secret,
            client_secret: secret,
            merchant_id: secret,
            api_key: secret,
            secret_key: secret,
            webhook_secret: secret
          }
        },
        settings: %Schema{
          type: :object,
          properties: %{source_code: %Schema{type: :string, maxLength: 100}}
        }
      },
      required: [:environment, :provider]
    }
  end

  @doc "ADR-291: a package waiting to be paid at the front desk («Περιμένει πληρωμή»)."
  def package_request do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        user_id: @uuid,
        package_id: @uuid,
        package_name: %Schema{type: :string},
        price_cents: @int,
        currency: %Schema{type: :string},
        status: %Schema{type: :string, enum: ~w(pending activated cancelled lapsed)},
        source: %Schema{type: :string, enum: ~w(member staff)},
        requested_at: %Schema{type: :string, format: :"date-time"},
        hold_until: %Schema{
          type: :string,
          format: :date,
          description: "The box's last day the package is held; it is removed the day after"
        },
        hold_days: @int,
        days_left: @int,
        person: %Schema{
          type: :object,
          nullable: true,
          description: "Staff queue only: who asked, to open their account",
          properties: %{
            user_id: @uuid,
            display_name: @text,
            handle: @text,
            avatar_url: @text
          }
        }
      },
      required: [
        :currency,
        :days_left,
        :hold_days,
        :hold_until,
        :id,
        :package_id,
        :package_name,
        :price_cents,
        :requested_at,
        :source,
        :status,
        :user_id
      ]
    }
  end

  def package_request_list,
    do: one(:requests, %Schema{type: :array, items: package_request()})

  def package_request_created do
    %Schema{
      type: :object,
      properties: %{request: package_request(), created: %Schema{type: :boolean}},
      required: [:created, :request]
    }
  end

  def package_request_collect_body do
    %Schema{
      type: :object,
      properties: %{
        payment_method: %Schema{type: :string, enum: ~w(cash card_manual bank_transfer other)},
        notes: %{@text | maxLength: 500}
      },
      required: [:payment_method]
    }
  end

  def intent do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        provider: %Schema{type: :string},
        environment: %Schema{type: :string},
        user_id: %{@uuid | nullable: true},
        initiation: %Schema{type: :string, enum: ["payer", "merchant", "terminal"]},
        purpose_type: %Schema{type: :string},
        purpose_id: @uuid,
        amount_cents: @int,
        currency: %Schema{type: :string},
        description: %Schema{type: :string},
        status: %Schema{
          type: :string,
          enum: ~w(scheduled awaiting_payer processing succeeded failed cancelled expired)
        },
        redirect_url: @text,
        provider_transaction_id: @text,
        card_brand: @text,
        card_last4: @text,
        refunded_cents: @int,
        failure_code: @text,
        fulfilment_status: %Schema{type: :string},
        finance_payment_id: %{@uuid | nullable: true},
        expires_at: @time,
        succeeded_at: @time,
        next_attempt_at: @time,
        inserted_at: @time,
        metadata: %Schema{type: :object, additionalProperties: true},
        attention_resolved_at: @time,
        attention_resolution: @text,
        declines: @int,
        retries: @int
      },
      required: [
        :amount_cents,
        :currency,
        :declines,
        :description,
        :environment,
        :fulfilment_status,
        :id,
        :initiation,
        :provider,
        :purpose_id,
        :purpose_type,
        :refunded_cents,
        :retries,
        :status
      ]
    }
  end

  def refund do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        amount_cents: @int,
        currency: %Schema{type: :string},
        status: %Schema{type: :string, enum: ["pending", "succeeded", "failed"]},
        reason: @text,
        failure_message: @text,
        finance_reversal_id: %Schema{@uuid | nullable: true},
        completed_at: @time,
        inserted_at: @time
      },
      required: [:amount_cents, :currency, :id, :status]
    }
  end

  def intent_detail do
    %Schema{
      allOf: [
        intent(),
        %Schema{
          type: :object,
          properties: %{refunds: %Schema{type: :array, items: refund()}},
          required: [:refunds]
        }
      ]
    }
  end

  @doc "ADR-260: the Εκκρεμότητες tab names the person each charge is for."
  def attention_page do
    item = %Schema{
      allOf: [
        intent(),
        %Schema{
          type: :object,
          properties: %{member_name: @text},
          required: [:member_name]
        }
      ]
    }

    %Schema{
      type: :object,
      properties: %{payments: %Schema{type: :array, items: item}, total: @int},
      required: [:payments, :total]
    }
  end

  def intent_page do
    %Schema{
      type: :object,
      properties: %{payments: %Schema{type: :array, items: intent()}, total: @int},
      required: [:payments, :total]
    }
  end

  def refund_body do
    %Schema{
      type: :object,
      properties: %{
        amount_cents: %Schema{type: :integer, minimum: 1},
        reason: %Schema{type: :string, maxLength: 300},
        idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 200}
      },
      required: [:amount_cents, :idempotency_key]
    }
  end

  def method do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        provider: %Schema{type: :string},
        brand: @text,
        last4: @text,
        exp_month: %{@int | nullable: true},
        exp_year: %{@int | nullable: true},
        status: %Schema{type: :string, enum: ["active", "revoked"]},
        autopay: %Schema{type: :boolean},
        max_amount_cents: @int,
        currency: %Schema{type: :string},
        consented_at: @time,
        consent_version: @text
      },
      required: [:autopay, :currency, :id, :max_amount_cents, :provider, :status]
    }
  end

  def checkout_terms do
    %Schema{
      type: :object,
      properties: %{
        available: %Schema{type: :boolean},
        amount_cents: @int,
        currency: %Schema{type: :string},
        provider: %Schema{
          type: :string,
          nullable: true,
          description: "The provider members pay through, or null when online payment is off"
        },
        consent_text: %Schema{type: :string},
        consent_version: %Schema{type: :string}
      },
      required: [
        :amount_cents,
        :available,
        :consent_text,
        :consent_version,
        :currency,
        :provider
      ]
    }
  end

  def pay_body do
    %Schema{
      type: :object,
      properties: %{
        idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 200},
        save_card: %Schema{type: :boolean},
        consent_accepted: %Schema{type: :boolean},
        autopay: %Schema{
          type: :boolean,
          description: "With save_card: pay what falls due with this card"
        },
        language: %Schema{type: :string, enum: ["el", "en"]}
      },
      required: [:idempotency_key]
    }
  end

  def return_body do
    %Schema{
      type: :object,
      properties: %{
        payment_id: @uuid,
        provider_ref: %Schema{type: :string, maxLength: 200},
        transaction_id: %Schema{type: :string, maxLength: 200}
      }
    }
  end

  def autopay_body do
    %Schema{
      type: :object,
      properties: %{autopay: %Schema{type: :boolean}},
      required: [:autopay]
    }
  end

  def sandbox_body do
    %Schema{
      type: :object,
      properties: %{
        provider_ref: %Schema{type: :string, maxLength: 200},
        outcome: %Schema{type: :string, enum: ["succeeded", "failed", "cancelled"]},
        decline_card: %Schema{type: :boolean}
      },
      required: [:outcome, :provider_ref]
    }
  end

  # ── ADR-248: online sales ───────────────────────────────────────────────

  def public_package do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        description: @text,
        package_type: %Schema{type: :string},
        billing_period: %Schema{type: :string},
        base_price_cents: @int,
        currency: %Schema{type: :string},
        services: %Schema{
          type: :object,
          description:
            "The package's in-person services (ADR-256): the store apps sell only packages with one",
          additionalProperties: true
        }
      },
      required: [
        :base_price_cents,
        :billing_period,
        :currency,
        :id,
        :name,
        :package_type,
        :services
      ]
    }
  end

  def public_packages do
    %Schema{
      type: :object,
      properties: %{
        packages: %Schema{type: :array, items: public_package()},
        online_payments: %Schema{type: :boolean},
        provider: %Schema{
          type: :string,
          nullable: true,
          description: "The provider members pay through, or null when online payment is off"
        },
        withdrawal_days: %{@int | nullable: true}
      },
      required: [:online_payments, :packages, :provider, :withdrawal_days]
    }
  end

  def package_terms do
    %Schema{
      type: :object,
      properties: %{
        package: public_package(),
        available: %Schema{type: :boolean},
        provider: %Schema{
          type: :string,
          nullable: true,
          description: "The provider members pay through, or null when online payment is off"
        },
        withdrawal_days: %{@int | nullable: true},
        start_now_text: @text,
        consent_text: %Schema{type: :string},
        consent_version: %Schema{type: :string}
      },
      required: [
        :available,
        :consent_text,
        :consent_version,
        :package,
        :provider,
        :start_now_text,
        :withdrawal_days
      ]
    }
  end

  def buy_body do
    %Schema{
      type: :object,
      properties: %{
        idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 200},
        save_card: %Schema{type: :boolean},
        consent_accepted: %Schema{type: :boolean},
        start_now: %Schema{type: :boolean},
        autopay: %Schema{
          type: :boolean,
          description: "With save_card: pay what falls due with this card"
        },
        language: %Schema{type: :string, enum: ["el", "en"]},
        book_slot_id: @uuid
      },
      required: [:idempotency_key]
    }
  end

  def withdrawal do
    %Schema{
      type: :object,
      properties: %{
        refund: %Schema{type: :object, additionalProperties: true},
        refunded_cents: @int
      },
      required: [:refund, :refunded_cents]
    }
  end

  def shop_pay_body do
    %Schema{
      type: :object,
      properties: %{
        idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 200},
        language: %Schema{type: :string, enum: ["el", "en"]}
      },
      required: [:idempotency_key]
    }
  end
end
