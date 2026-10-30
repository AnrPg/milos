defmodule PaleeWeb.Schemas.MyBilling do
  @moduledoc """
  OpenAPI shape of Εγώ › Πληρωμές & αποδείξεις (`GET /api/me/billing`): one
  section per provider the person is a client of.
  """

  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @date %Schema{type: :string, format: :date, nullable: true}
  @datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @string %Schema{type: :string}
  @nullable_string %Schema{type: :string, nullable: true}
  @integer %Schema{type: :integer}
  @nullable_integer %Schema{type: :integer, nullable: true}
  @boolean %Schema{type: :boolean}

  defp object(title, required, properties) do
    %Schema{title: title, type: :object, required: required, properties: properties}
  end

  defp list(items), do: %Schema{type: :array, items: items}

  defp membership do
    %Schema{
      title: "BillingMembership",
      type: :object,
      nullable: true,
      required: [:status],
      properties: %{
        status: @string,
        entitlement_status: @nullable_string,
        starts_on: @date,
        expires_on: @date,
        leaving_on: %Schema{
          type: :string,
          format: :date,
          nullable: true,
          description: "ADR-220: the member is leaving (or left) the box; their last day."
        },
        left_by: %Schema{type: :string, enum: ["member", "staff"], nullable: true},
        leave_reason: @nullable_string,
        leave_preview_on: %Schema{
          type: :string,
          format: :date,
          nullable: true,
          description: "ADR-220: the last day the member would keep if they left today."
        }
      }
    }
  end

  defp subscription do
    object("BillingSubscription", [:id, :status, :current], %{
      id: @uuid,
      status: @string,
      current: %Schema{type: :boolean, description: "The package in force today."},
      package_name: @nullable_string,
      package_type: @nullable_string,
      billing_period: @nullable_string,
      price_cents: @nullable_integer,
      starts_on: @date,
      ends_on: @date,
      commitment_ends_on: @date,
      auto_renew: %Schema{
        type: :boolean,
        nullable: true,
        description:
          "ADR-220: the member's renewal choice; null when the package does not renew or the choice is not theirs."
      },
      can_change_auto_renew: %Schema{
        type: :boolean,
        description: "The member can turn renewal of this subscription on or off."
      },
      corporate: @boolean
    })
  end

  defp invoice do
    object(
      "BillingInvoice",
      [:id, :document_kind, :status, :total_cents, :balance_due_cents, :currency, :downloadable],
      %{
        id: @uuid,
        invoice_number: @nullable_string,
        document_kind: %Schema{type: :string, enum: ["invoice", "receipt"]},
        status: @string,
        issue_date: @date,
        due_date: @date,
        total_cents: @integer,
        balance_due_cents: @integer,
        currency: @string,
        downloadable: %Schema{type: :boolean, description: "A PDF is on file to download."}
      }
    )
  end

  defp payment do
    object("BillingPayment", [:id, :currency], %{
      id: @uuid,
      amount_cents: @nullable_integer,
      net_amount_cents: @nullable_integer,
      currency: @string,
      paid_on: @date,
      payment_method: @nullable_string,
      payment_status: @nullable_string,
      finance_invoice_id: @nullable_uuid
    })
  end

  defp refund_receipt do
    object("BillingRefundReceipt", [:id, :receipt_number, :amount_cents, :currency], %{
      id: @uuid,
      receipt_number: @string,
      reversal_type: @string,
      amount_cents: @integer,
      currency: @string,
      reason: @nullable_string,
      issued_at: @datetime,
      invoice_number: @nullable_string
    })
  end

  defp promotion do
    object("BillingPromotion", [:id], %{
      id: @uuid,
      campaign_name: @nullable_string,
      discount_type: @nullable_string,
      discount_value: @nullable_integer,
      redeemed_at: @datetime
    })
  end

  defp season do
    object("BillingSeason", [:id, :season_id, :title, :status], %{
      id: @uuid,
      season_id: @uuid,
      title: @string,
      status: @string,
      starts_on: @date,
      ends_on: @date,
      price_cents: @integer,
      currency: @string
    })
  end

  defp referrals do
    object(
      "BillingReferrals",
      [:credits, :credit_total_cents, :invited, :trials, :paid],
      %{
        credits:
          list(
            object("BillingReferralCredit", [:id, :amount_cents, :currency], %{
              id: @uuid,
              amount_cents: @integer,
              currency: @string,
              description: @nullable_string,
              occurred_on: @date
            })
          ),
        credit_total_cents: @integer,
        invited: @integer,
        trials: @integer,
        paid: @integer
      }
    )
  end

  defp trial do
    object("BillingTrial", [:id, :status], %{
      id: @uuid,
      status: @string,
      class_name: @nullable_string,
      class_starts_at: @datetime
    })
  end

  defp available_offer do
    object("BillingAvailableOffer", [:id, :code], %{
      id: @uuid,
      code: @string,
      campaign_name: @nullable_string,
      description: @nullable_string,
      discount_type: @nullable_string,
      discount_value: @nullable_integer,
      ends_on: @date
    })
  end

  defp perk do
    %Schema{
      title: "BillingPerk",
      type: :object,
      description:
        "A partner perk (ADR-191) the person claimed at this provider and can still use, read from the version they agreed to: `discount` is the benefit in one line, `code` what to give the partner (the claim's reference for a show-your-membership perk), `url` the store link with the code applied, else the partner's site. Perks not claimed yet are listed by `GET /api/me/perks`.",
      required: [:id, :store, :code],
      properties: %{
        id: @uuid,
        store: @string,
        discount: @nullable_string,
        code: @string,
        terms: @nullable_string,
        valid_until: @date,
        url: @nullable_string
      }
    }
  end

  defp provider do
    object(
      "BillingProvider",
      [
        :organization_id,
        :name,
        :slug,
        :kind,
        :partial,
        :contact,
        :actions,
        :subscriptions,
        :invoices,
        :payments,
        :refund_receipts,
        :promotions,
        :seasons,
        :referrals,
        :trials,
        :available_offers,
        :perks,
        :outstanding_cents,
        :credit_balance_cents
      ],
      %{
        organization_id: @uuid,
        name: @string,
        slug: @string,
        kind: %Schema{type: :string, enum: ["gym", "coach"]},
        logo_url: @nullable_string,
        primary_color: @nullable_string,
        partial: %Schema{type: :boolean, description: "Some sections could not be read."},
        contact:
          object("BillingContact", [:box_chat_slug], %{
            box_chat_slug: %Schema{
              type: :string,
              nullable: true,
              description: "The box whose chat reaches it (`/b/{slug}/chat`, ADR-282: published or not)."
            }
          }),
        actions:
          object(
            "BillingActions",
            [
              :self_service_purchase,
              :self_service_cancel_auto_renew,
              :self_service_leave,
              :download_invoices
            ],
            %{
              self_service_purchase: @boolean,
              self_service_cancel_auto_renew: @boolean,
              self_service_leave: @boolean,
              download_invoices: @boolean
            }
          ),
        membership: membership(),
        entitlement: %Schema{
          type: :object,
          nullable: true,
          additionalProperties: true,
          description: "The effective entitlement (remaining allowances), without usage entries."
        },
        subscriptions: list(subscription()),
        invoices: list(invoice()),
        payments: list(payment()),
        refund_receipts: list(refund_receipt()),
        promotions: list(promotion()),
        seasons: list(season()),
        referrals: referrals(),
        trials: list(trial()),
        available_offers: %Schema{
          type: :array,
          items: available_offer(),
          description: "Codes of running campaigns the box shows to members."
        },
        perks: %Schema{type: :array, items: perk()},
        outstanding_cents: @integer,
        credit_balance_cents: @integer
      }
    )
  end

  # `shop_order` is reserved for shop purchases (post-MVP, TD-189).
  @transaction_kinds ~w(invoice payment refund credit event_payment event_refund shop_order)

  def transaction_kinds, do: @transaction_kinds

  defp transaction do
    object(
      "BillingTransaction",
      [:id, :kind, :source_id, :counterparty, :amount_cents, :currency, :details],
      %{
        id: %Schema{type: :string, description: "`kind:source_id`, stable across pages."},
        kind: %Schema{type: :string, enum: @transaction_kinds},
        source_id: %Schema{type: :string},
        counterparty:
          object("BillingCounterparty", [:organization_id, :kind], %{
            organization_id: @uuid,
            name: @nullable_string,
            kind: %Schema{type: :string, enum: ["gym", "coach", "organiser"]},
            slug: @nullable_string
          }),
        title: @nullable_string,
        source_url: %Schema{
          type: :string,
          nullable: true,
          description: "In-app path of the source's own page when it has one (e.g. a shop order)."
        },
        amount_cents: %Schema{type: :integer, description: "Negative for money back."},
        currency: @string,
        status: @nullable_string,
        date: @datetime,
        details: %Schema{
          type: :object,
          additionalProperties: true,
          description:
            "Per kind: invoice number, due date, balance, lines and `downloadable`; payment method; refund reason and receipt; event id."
        }
      }
    )
  end

  def transactions_response do
    object(
      "MyBillingTransactions",
      [:transactions, :next_cursor, :total, :kinds, :partial],
      %{
        transactions: list(transaction()),
        next_cursor: @nullable_string,
        total: %Schema{type: :integer, description: "Entries in scope, before the kind filter."},
        kinds: %Schema{type: :array, items: %Schema{type: :string, enum: @transaction_kinds}},
        partial: @boolean
      }
    )
  end

  def response do
    object("MyBilling", [:providers], %{providers: list(provider())})
  end
end
