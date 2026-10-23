defmodule PaleeWeb.Schemas.Shop do
  @moduledoc "OpenAPI schemas of the e-shop (ADR-190)."

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @time %Schema{type: :string, format: :"date-time", nullable: true}
  @date %Schema{type: :string, format: :date, nullable: true}
  @text %Schema{type: :string, nullable: true}
  @cents %Schema{type: :integer, minimum: 0}
  @nullable_cents %Schema{type: :integer, minimum: 0, nullable: true}
  @currency %Schema{type: :string, pattern: "^[A-Z]{3}$"}
  @stream %Schema{type: :string, enum: ~w(membership package event shop other)}
  @states ~w(pending_payment paid ready_for_pickup picked_up cancelled partially_refunded refunded)

  def uuid, do: @uuid

  def id_param(name \\ :id),
    do: %Parameter{name: name, in: :path, required: true, schema: @uuid}

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def one(key, schema), do: %Schema{type: :object, properties: %{key => schema}, required: [key]}
  def many(key, schema), do: one(key, %Schema{type: :array, items: schema})

  # ── Catalog ──────────────────────────────────────────────────────────────

  def option_axis do
    %Schema{
      title: "ShopOptionAxis",
      type: :object,
      properties: %{
        name: %Schema{type: :string, minLength: 1, maxLength: 40},
        values: %Schema{
          type: :array,
          items: %Schema{type: :string, maxLength: 40},
          minItems: 1,
          maxItems: 50
        }
      },
      required: [:name, :values]
    }
  end

  def stock do
    %Schema{
      title: "ShopVariantStock",
      type: :object,
      properties: %{
        on_hand: %Schema{type: :integer},
        reserved: %Schema{type: :integer},
        available: %Schema{type: :integer},
        by_location: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              location_id: @nullable_uuid,
              on_hand: %Schema{type: :integer},
              reserved: %Schema{type: :integer},
              available: %Schema{type: :integer}
            }
          }
        }
      },
      required: [:on_hand, :reserved, :available]
    }
  end

  def variant do
    %Schema{
      title: "ShopVariant",
      type: :object,
      properties: %{
        id: @uuid,
        product_id: @uuid,
        title: @text,
        option_values: %Schema{type: :object, additionalProperties: %Schema{type: :string}},
        sku: @text,
        barcode: @text,
        price_cents: @cents,
        currency: @currency,
        compare_at_price_cents: @nullable_cents,
        cost_price_cents: @nullable_cents,
        tax_class: @text,
        low_stock_threshold: %Schema{type: :integer, nullable: true},
        track_inventory: %Schema{type: :boolean},
        stock_status: %Schema{type: :string, enum: ~w(ok low critical out)},
        position: %Schema{type: :integer},
        archived_at: @time,
        stock: stock()
      },
      required: [:id, :product_id, :price_cents, :currency, :stock_status]
    }
  end

  @product_props %{
    title: %Schema{type: :string, minLength: 1, maxLength: 160},
    description: %Schema{type: :string, maxLength: 8000, nullable: true},
    category: %Schema{type: :string, maxLength: 80, nullable: true},
    media_ids: %Schema{type: :array, items: @uuid, maxItems: 12},
    visibility: %Schema{type: :string, enum: ["members_only", "anyone"]},
    sell_in_app: %Schema{type: :boolean},
    sell_at_desk: %Schema{type: :boolean},
    member_discount_applies: %Schema{type: :boolean},
    per_person_limit: %Schema{type: :integer, minimum: 1, nullable: true},
    all_locations: %Schema{type: :boolean},
    location_ids: %Schema{type: :array, items: @uuid, maxItems: 200},
    position: %Schema{type: :integer}
  }

  def product do
    %Schema{
      title: "ShopProduct",
      type: :object,
      properties:
        Map.merge(@product_props, %{
          id: @uuid,
          status: %Schema{type: :string, enum: ["draft", "published", "archived"]},
          options: %Schema{
            type: :object,
            properties: %{axes: %Schema{type: :array, items: option_axis()}}
          },
          published_at: @time,
          archived_at: @time,
          media: %Schema{
            type: :array,
            items: product_photo(),
            description: "The photos of media_ids, resolved (ready ones only, in order)"
          },
          variants: %Schema{type: :array, items: variant()}
        }),
      required: [:id, :title, :status, :visibility, :variants]
    }
  end

  def product_photo do
    %Schema{
      title: "ShopProductPhoto",
      type: :object,
      properties: %{
        id: @uuid,
        url: @text,
        thumb_url: @text,
        full_url: @text,
        width: %Schema{type: :integer, nullable: true},
        height: %Schema{type: :integer, nullable: true},
        alt_text: @text
      },
      required: [:id]
    }
  end

  @status %Schema{type: :string, enum: ["draft", "published", "archived"]}

  @variant_body_props %{
    option_values: %Schema{type: :object, additionalProperties: %Schema{type: :string}},
    title: %Schema{type: :string, maxLength: 160, nullable: true},
    sku: %Schema{type: :string, maxLength: 64, nullable: true},
    barcode: %Schema{type: :string, maxLength: 64, nullable: true},
    price_cents: @cents,
    currency: @currency,
    compare_at_price_cents: @nullable_cents,
    cost_price_cents: @nullable_cents,
    tax_class: %Schema{
      type: :string,
      enum: ~w(standard reduced super_reduced zero exempt),
      nullable: true
    },
    low_stock_threshold: %Schema{type: :integer, minimum: 0, nullable: true},
    track_inventory: %Schema{type: :boolean},
    position: %Schema{type: :integer}
  }

  def variant_body do
    %Schema{
      title: "ShopVariantBody",
      type: :object,
      additionalProperties: false,
      properties: @variant_body_props
    }
  end

  def product_body do
    %Schema{
      title: "ShopProductBody",
      type: :object,
      additionalProperties: false,
      properties:
        Map.merge(@product_props, %{
          options: %Schema{type: :array, items: option_axis(), maxItems: 2},
          price_cents: @cents,
          status: %{
            @status
            | description:
                "Created as a draft unless given; published runs the publish checks in the same transaction"
          },
          variants: %Schema{
            type: :array,
            minItems: 1,
            maxItems: 200,
            items: %Schema{
              type: :object,
              additionalProperties: false,
              properties:
                Map.merge(@variant_body_props, %{
                  initial_quantity: %Schema{type: :integer, minimum: 0},
                  location_id: @nullable_uuid
                }),
              required: [:price_cents]
            }
          }
        }),
      required: [:title]
    }
  end

  def product_update_body do
    %Schema{
      title: "ShopProductUpdateBody",
      type: :object,
      additionalProperties: false,
      properties:
        Map.merge(@product_props, %{
          options: %Schema{type: :array, items: option_axis(), maxItems: 2},
          status: @status,
          variants: %Schema{
            type: :array,
            minItems: 1,
            maxItems: 200,
            description:
              "The full list of live variants: with id edited, without one added (with optional opening stock), live ones left out archived. Written with the product in one transaction.",
            items: %Schema{
              type: :object,
              additionalProperties: false,
              properties:
                Map.merge(@variant_body_props, %{
                  id: @nullable_uuid,
                  initial_quantity: %Schema{type: :integer, minimum: 0},
                  location_id: @nullable_uuid
                })
            }
          }
        })
    }
  end

  def status_body do
    %Schema{
      title: "ShopProductStatusBody",
      type: :object,
      additionalProperties: false,
      properties: %{status: %Schema{type: :string, enum: ["draft", "published", "archived"]}},
      required: [:status]
    }
  end

  # ── Stock ────────────────────────────────────────────────────────────────

  def movement do
    %Schema{
      title: "ShopStockMovement",
      type: :object,
      properties: %{
        id: @uuid,
        variant_id: @uuid,
        location_id: @nullable_uuid,
        kind: %Schema{
          type: :string,
          enum: ~w(receive sale refund_restock adjustment transfer reserve release)
        },
        quantity: %Schema{type: :integer},
        reason: @text,
        note: @text,
        unit_cost_cents: @nullable_cents,
        order_id: @nullable_uuid,
        order_line_id: @nullable_uuid,
        transfer_id: @nullable_uuid,
        user_id: @nullable_uuid,
        occurred_at: @time
      },
      required: [:id, :variant_id, :kind, :quantity]
    }
  end

  def movement_body do
    %Schema{
      title: "ShopStockMovementBody",
      type: :object,
      additionalProperties: false,
      properties: %{
        kind: %Schema{type: :string, enum: ~w(receive adjustment recount transfer)},
        quantity: %Schema{type: :integer},
        counted: %Schema{type: :integer, minimum: 0},
        reason: %Schema{type: :string, enum: ~w(recount damage loss return other)},
        note: %Schema{type: :string, maxLength: 1000, nullable: true},
        unit_cost_cents: @nullable_cents,
        location_id: @nullable_uuid,
        to_location_id: @nullable_uuid
      },
      required: [:kind]
    }
  end

  # ── Orders ───────────────────────────────────────────────────────────────

  def order_line do
    %Schema{
      title: "ShopOrderLine",
      type: :object,
      properties: %{
        id: @uuid,
        product_id: @uuid,
        variant_id: @uuid,
        product_title: %Schema{type: :string},
        variant_title: @text,
        sku: @text,
        quantity: %Schema{type: :integer},
        unit_price_cents: @cents,
        discount_cents: @cents,
        total_cents: @cents,
        refunded_quantity: %Schema{type: :integer},
        refunded_cents: @cents,
        location_id: @nullable_uuid,
        finance_invoice_line_id: @nullable_uuid
      },
      required: [:id, :variant_id, :product_title, :quantity, :total_cents]
    }
  end

  def order do
    %Schema{
      title: "ShopOrder",
      type: :object,
      properties: %{
        id: @uuid,
        number: %Schema{type: :integer},
        pickup_code: %Schema{
          type: :string,
          nullable: true,
          description: "The short code the buyer shows at the desk"
        },
        state: %Schema{type: :string, enum: @states},
        status: %Schema{type: :string, enum: ~w(placed ready_for_pickup picked_up cancelled)},
        payment_status: %Schema{
          type: :string,
          enum: ~w(pending_payment paid partially_refunded refunded void)
        },
        channel: %Schema{type: :string, enum: ["online", "pos"]},
        payment_mode: %Schema{type: :string},
        user_id: @nullable_uuid,
        customer_name: @text,
        pickup_location_id: @nullable_uuid,
        currency: @currency,
        subtotal_cents: @cents,
        discount_cents: @cents,
        total_cents: @cents,
        paid_cents: @cents,
        refunded_cents: @cents,
        source: %Schema{type: :string},
        source_ref_id: @nullable_uuid,
        promotion_code: @text,
        finance_invoice_id: @nullable_uuid,
        fiscal_receipt_ref: @text,
        revenue_stream: @stream,
        placed_at: @time,
        expires_at: @time,
        paid_at: @time,
        ready_at: @time,
        picked_up_at: @time,
        cancelled_at: @time,
        cancel_reason: @text,
        lines: %Schema{type: :array, items: order_line()}
      },
      required: [:id, :number, :state, :status, :payment_status, :channel, :total_cents, :lines]
    }
  end

  def cart_item do
    %Schema{
      title: "ShopCartItem",
      type: :object,
      additionalProperties: false,
      properties: %{variant_id: @uuid, quantity: %Schema{type: :integer, minimum: 1, maximum: 99}},
      required: [:variant_id, :quantity]
    }
  end

  def online_payment do
    %Schema{
      title: "ShopOnlinePayment",
      description: "Whether online card payment can be offered; false greys out «Πληρωμή».",
      type: :object,
      properties: %{
        available: %Schema{type: :boolean},
        reason: %Schema{type: :string, nullable: true, description: "e.g. no_provider"},
        provider: %Schema{type: :string}
      },
      required: [:available]
    }
  end

  def cart_body do
    %Schema{
      title: "ShopCartBody",
      type: :object,
      additionalProperties: false,
      properties: %{
        lines: %Schema{type: :array, items: cart_item(), minItems: 1, maxItems: 50},
        pickup_location_id: @nullable_uuid,
        promotion_code: %Schema{type: :string, maxLength: 64, nullable: true}
      },
      required: [:lines]
    }
  end

  def preview do
    %Schema{
      title: "ShopCartPreview",
      type: :object,
      properties: %{
        lines: %Schema{type: :array, items: %Schema{type: :object, additionalProperties: true}},
        currency: @currency,
        subtotal_cents: @cents,
        discount_cents: @cents,
        total_cents: @cents,
        pickup_location_id: @nullable_uuid,
        pickup_location_ids: %Schema{type: :array, items: @uuid},
        payment_modes: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: ["at_pickup", "on_account", "online"]}
        },
        online_payment: online_payment(),
        promotion_code_id: @nullable_uuid,
        member_discount: member_discount(),
        promotion_code: %Schema{
          type: :object,
          nullable: true,
          description: "The promotion code that applied (never stacked with the member discount)",
          properties: %{id: @uuid, code: %Schema{type: :string}, applied: %Schema{type: :boolean}}
        }
      },
      required: [:lines, :total_cents, :payment_modes, :online_payment]
    }
  end

  @attribution %{
    source: %Schema{
      type: :string,
      enum: ~w(direct club_post promotion_code desk public_page other)
    },
    source_ref_id: @nullable_uuid,
    promotion_code: %Schema{type: :string, maxLength: 64, nullable: true},
    note: %Schema{type: :string, maxLength: 1000, nullable: true},
    idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 120}
  }

  def checkout_body do
    %Schema{
      title: "ShopCheckoutBody",
      type: :object,
      additionalProperties: false,
      properties:
        Map.merge(@attribution, %{
          lines: %Schema{type: :array, items: cart_item(), minItems: 1, maxItems: 50},
          pickup_location_id: @nullable_uuid,
          payment_mode: %Schema{type: :string, enum: ["at_pickup", "on_account", "online"]},
          payment_token: %Schema{type: :string, maxLength: 200, nullable: true}
        }),
      required: [:lines, :idempotency_key]
    }
  end

  def pay_body do
    %Schema{
      title: "ShopPayBody",
      type: :object,
      additionalProperties: false,
      properties: %{payment_token: %Schema{type: :string, maxLength: 200}},
      required: [:payment_token]
    }
  end

  @desk_method %Schema{type: :string, enum: ~w(cash card_manual bank_transfer other)}

  def desk_sale_body do
    %Schema{
      title: "ShopDeskSaleBody",
      type: :object,
      additionalProperties: false,
      properties:
        Map.merge(Map.delete(@attribution, :source), %{
          lines: %Schema{type: :array, items: cart_item(), minItems: 1, maxItems: 50},
          payment_method: @desk_method,
          user_id: @nullable_uuid,
          customer_name: %Schema{type: :string, maxLength: 160, nullable: true},
          location_id: @nullable_uuid
        }),
      required: [:lines, :payment_method, :idempotency_key]
    }
  end

  def payment_body do
    %Schema{
      title: "ShopOrderPaymentBody",
      type: :object,
      additionalProperties: false,
      properties: %{payment_method: @desk_method},
      required: [:payment_method]
    }
  end

  def pickup_body do
    %Schema{
      title: "ShopOrderPickupBody",
      type: :object,
      additionalProperties: false,
      properties: %{payment_method: @desk_method}
    }
  end

  def cancel_body do
    %Schema{
      title: "ShopOrderCancelBody",
      type: :object,
      additionalProperties: false,
      properties: %{reason: %Schema{type: :string, maxLength: 500, nullable: true}}
    }
  end

  def refund_body do
    %Schema{
      title: "ShopRefundBody",
      type: :object,
      additionalProperties: false,
      properties: %{
        lines: %Schema{
          type: :array,
          minItems: 1,
          items: %Schema{
            type: :object,
            additionalProperties: false,
            properties: %{
              order_line_id: @uuid,
              quantity: %Schema{type: :integer, minimum: 1},
              restock: %Schema{type: :boolean}
            },
            required: [:order_line_id, :quantity]
          }
        },
        reason: %Schema{type: :string, maxLength: 500, nullable: true},
        idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 120}
      },
      required: [:lines, :idempotency_key]
    }
  end

  def fiscal_receipt_body do
    %Schema{
      title: "ShopFiscalReceiptBody",
      type: :object,
      additionalProperties: false,
      properties: %{fiscal_receipt_ref: %Schema{type: :string, maxLength: 120, nullable: true}},
      required: [:fiscal_receipt_ref]
    }
  end

  # ── Finance lineage ──────────────────────────────────────────────────────

  def revenue_stream_total do
    %Schema{
      title: "RevenueStreamTotal",
      type: :object,
      properties: %{
        revenue_stream: @stream,
        currency: @currency,
        paid_cents: %Schema{type: :integer},
        refunded_cents: %Schema{type: :integer},
        net_cents: %Schema{type: :integer}
      },
      required: [:revenue_stream, :currency, :paid_cents, :refunded_cents, :net_cents]
    }
  end

  def revenue_streams do
    %Schema{
      title: "RevenueStreams",
      type: :object,
      properties: %{
        from: @date,
        to: @date,
        streams: %Schema{type: :array, items: revenue_stream_total()}
      },
      required: [:streams]
    }
  end

  def lineage do
    row = %Schema{type: :object, additionalProperties: true}

    %Schema{
      title: "ShopOrderLineage",
      description:
        "Every Finance row of an order: invoice lines (source shop_order_line), the payment and refunds (source shop_order), and the stock movements.",
      type: :object,
      properties: %{
        order: order(),
        invoice_lines: %Schema{type: :array, items: row},
        payments: %Schema{type: :array, items: row},
        reversals: %Schema{type: :array, items: row},
        movements: %Schema{type: :array, items: movement()}
      },
      required: [:order, :invoice_lines, :payments, :reversals, :movements]
    }
  end

  # ── Member views ─────────────────────────────────────────────────────────

  def member_variant do
    %Schema{
      title: "ShopMemberVariant",
      type: :object,
      properties: %{
        id: @uuid,
        product_id: @uuid,
        title: @text,
        option_values: %Schema{type: :object, additionalProperties: %Schema{type: :string}},
        sku: @text,
        price_cents: @cents,
        currency: @currency,
        compare_at_price_cents: @nullable_cents,
        available: %Schema{type: :string, enum: ["in_stock", "low", "sold_out"]}
      },
      required: [:id, :price_cents, :currency, :available]
    }
  end

  def member_product do
    %Schema{
      title: "ShopMemberProduct",
      type: :object,
      properties: %{
        id: @uuid,
        title: %Schema{type: :string},
        description: @text,
        category: @text,
        media_ids: %Schema{type: :array, items: @uuid},
        media: %Schema{type: :array, items: product_photo()},
        options: %Schema{type: :object, additionalProperties: true},
        visibility: %Schema{type: :string, enum: ["members_only", "anyone"]},
        per_person_limit: %Schema{type: :integer, nullable: true},
        all_locations: %Schema{type: :boolean},
        location_ids: %Schema{type: :array, items: @uuid},
        published_at: @time,
        variants: %Schema{type: :array, items: member_variant()}
      },
      required: [:id, :title, :variants]
    }
  end

  def transaction do
    %Schema{
      title: "ShopTransaction",
      type: :object,
      properties: %{
        kind: %Schema{type: :string, enum: ["shop_order"]},
        revenue_stream: @stream,
        order_id: @uuid,
        order_number: %Schema{type: :integer},
        state: %Schema{type: :string, enum: @states},
        channel: %Schema{type: :string},
        placed_at: @time,
        currency: @currency,
        total_cents: @cents,
        paid_cents: @cents,
        refunded_cents: @cents,
        finance_invoice_id: @nullable_uuid,
        invoice_number: @text,
        invoice_status: @text,
        fiscal_receipt_ref: @text,
        lines: %Schema{type: :array, items: %Schema{type: :object, additionalProperties: true}},
        payments: %Schema{type: :array, items: %Schema{type: :object, additionalProperties: true}},
        refunds: %Schema{type: :array, items: %Schema{type: :object, additionalProperties: true}}
      },
      required: [:kind, :revenue_stream, :order_id, :state, :total_cents]
    }
  end

  # ── «Προώθηση» ───────────────────────────────────────────────────────────

  @code_status ~w(active scheduled expired exhausted inactive)

  def promotion_code do
    %Schema{
      title: "ShopPromotionCode",
      type: :object,
      properties: %{
        id: @uuid,
        product_id: @uuid,
        code: %Schema{type: :string},
        discount_percent: %Schema{type: :integer, nullable: true},
        discount_cents: %Schema{type: :integer, nullable: true},
        max_redemptions: %Schema{type: :integer, nullable: true},
        redemptions: %Schema{type: :integer, description: "Orders (not cancelled) that used it"},
        starts_at: @time,
        ends_at: @time,
        active: %Schema{type: :boolean},
        status: %Schema{type: :string, enum: @code_status},
        post_id: @nullable_uuid,
        inserted_at: @time
      },
      required: [:id, :product_id, :code, :redemptions, :active, :status]
    }
  end

  @code_attrs %{
    discount_percent: %Schema{type: :integer, minimum: 1, maximum: 100, nullable: true},
    discount_cents: %Schema{
      type: :integer,
      minimum: 1,
      nullable: true,
      description: "Off each unit"
    },
    max_redemptions: %Schema{type: :integer, minimum: 1, nullable: true},
    starts_at: @time,
    ends_at: @time
  }

  def new_promotion_code do
    %Schema{
      title: "ShopNewPromotionCode",
      type: :object,
      additionalProperties: false,
      description: "A code of the promoted product: a percent off, or an amount off each unit",
      properties:
        Map.put(@code_attrs, :code, %Schema{
          type: :string,
          minLength: 3,
          maxLength: 32,
          description: "Letters, digits, - or _ (stored upper case)"
        }),
      required: [:code]
    }
  end

  def promotion_code_update_body do
    %Schema{
      title: "ShopPromotionCodeUpdateBody",
      type: :object,
      additionalProperties: false,
      properties: Map.put(@code_attrs, :active, %Schema{type: :boolean})
    }
  end

  def promote_body do
    %Schema{
      title: "ShopPromoteBody",
      type: :object,
      additionalProperties: false,
      properties: %{
        target: %Schema{
          type: :string,
          enum: Palee.Application.Shop.PromoteProduct.targets(),
          description:
            "announcements (club #ανακοινώσεις, default), channel (a member group or PT squad: channel_id) or feed (public: box page and followers)"
        },
        channel_id: @nullable_uuid,
        body: %Schema{type: :string, maxLength: 5000, nullable: true},
        promotion_code: %{new_promotion_code() | nullable: true},
        promotion_code_id: %{@nullable_uuid | description: "An existing code of this product"}
      }
    }
  end

  def product_card do
    %Schema{
      title: "ShopProductCard",
      type: :object,
      nullable: true,
      description:
        "The promoted product as the reader can buy it now (attachment_type product, ADR-190)",
      properties: %{
        product_id: @uuid,
        title: @text,
        media_ids: %Schema{type: :array, items: @uuid},
        status: %Schema{type: :string, enum: ~w(available sold_out members_only unavailable)},
        availability: %Schema{type: :string, enum: ~w(in_stock low), nullable: true},
        price_cents: %Schema{type: :integer, nullable: true},
        max_price_cents: %Schema{type: :integer, nullable: true},
        currency: %Schema{type: :string, nullable: true},
        promotion: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            code: %Schema{type: :string},
            discount_percent: %Schema{type: :integer, nullable: true},
            discount_cents: %Schema{type: :integer, nullable: true},
            ends_at: @time
          }
        },
        promotion_price_cents: %Schema{type: :integer, nullable: true},
        buy_link: %Schema{
          type: :object,
          nullable: true,
          description:
            "The in-app product route; an order placed from it sends these params as its attribution",
          properties: %{
            product_id: @uuid,
            path: %Schema{type: :string},
            url: %Schema{type: :string},
            params: %Schema{
              type: :object,
              properties: %{
                source: %Schema{type: :string},
                source_ref_id: @uuid,
                promotion_code: %Schema{type: :string}
              }
            }
          }
        }
      },
      required: [:product_id, :status]
    }
  end

  # ── Console lists ────────────────────────────────────────────────────────

  def product_list do
    %Schema{
      title: "ShopProductList",
      type: :object,
      properties: %{
        products: %Schema{type: :array, items: product()},
        counts: %Schema{
          type: :object,
          description: "Products per filter, within the branch and search filters",
          properties: %{
            all: %Schema{type: :integer},
            published: %Schema{type: :integer},
            draft: %Schema{type: :integer},
            archived: %Schema{type: :integer},
            low_stock: %Schema{type: :integer}
          },
          required: [:all, :published, :draft, :archived, :low_stock]
        }
      },
      required: [:products, :counts]
    }
  end

  def order_list do
    %Schema{
      title: "ShopOrderList",
      type: :object,
      properties: %{
        orders: %Schema{type: :array, items: order()},
        counts: %Schema{
          type: :object,
          description: "Orders per status, within the branch, buyer and paid filters",
          properties: %{
            placed: %Schema{type: :integer},
            ready_for_pickup: %Schema{type: :integer},
            picked_up: %Schema{type: :integer},
            cancelled: %Schema{type: :integer}
          },
          required: [:placed, :ready_for_pickup, :picked_up, :cancelled]
        }
      },
      required: [:orders, :counts]
    }
  end

  def ledger_movement do
    %{
      movement()
      | title: "ShopLedgerMovement",
        properties:
          Map.merge(movement().properties, %{
            product_id: @nullable_uuid,
            product_title: @text,
            variant_title: @text,
            sku: @text,
            order_number: %Schema{type: :integer, nullable: true},
            actor_name: @text
          })
    }
  end

  def ledger do
    %Schema{
      title: "ShopLedgerPage",
      type: :object,
      properties: %{
        movements: %Schema{type: :array, items: ledger_movement()},
        next_cursor: %Schema{type: :string, nullable: true}
      },
      required: [:movements]
    }
  end

  def payment_method do
    %Schema{
      title: "ShopPaymentMethod",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          description:
            "cash, card_manual (card at the terminal), bank_transfer, other, card_online"
        },
        channel: %Schema{type: :string, enum: ["pos", "online"]},
        available: %Schema{type: :boolean},
        reason: @text,
        provider: @text
      },
      required: [:id, :channel, :available]
    }
  end

  # ── Member storefront ────────────────────────────────────────────────────

  def member_discount do
    %Schema{
      title: "ShopMemberDiscount",
      type: :object,
      nullable: true,
      description:
        "The member's package discount: on products marked member_discount_applies, never stacked with a promotion code",
      properties: %{
        percent: %Schema{type: :integer},
        source: %Schema{type: :string, enum: ["membership_package"]},
        applies_to: %Schema{type: :string, enum: ["marked_products"]}
      },
      required: [:percent]
    }
  end

  def storefront do
    %Schema{
      title: "ShopStorefront",
      type: :object,
      properties: %{
        open: %Schema{type: :boolean},
        closed_reason: %Schema{
          type: :string,
          nullable: true,
          enum: ["no_products", "business_not_activated", nil]
        },
        products: %Schema{type: :array, items: member_product()},
        categories: %Schema{type: :array, items: %Schema{type: :string}},
        pickup_locations: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{id: @uuid, name: @text, address: @text},
            required: [:id]
          }
        },
        member_discount: member_discount(),
        online_payment: online_payment()
      },
      required: [:open, :products, :pickup_locations, :online_payment]
    }
  end

  def stock_alert do
    %Schema{
      title: "ShopStockAlert",
      type: :object,
      properties: %{
        id: @uuid,
        variant_id: @uuid,
        product_id: @nullable_uuid,
        notified_at: @time,
        inserted_at: @time,
        available: %Schema{type: :boolean, nullable: true}
      },
      required: [:id, :variant_id]
    }
  end
end
