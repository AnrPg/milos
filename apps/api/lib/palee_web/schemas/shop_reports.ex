defmodule PaleeWeb.Schemas.ShopReports do
  @moduledoc """
  OpenAPI shapes of the shop reports (ADR-192), shaped for the future
  «Κατάστημα › Αναλυτικά» tab. Money is integer cents; percentages are
  numbers with one decimal; ids are UUID strings.
  """

  alias OpenApiSpex.{Parameter, Schema}

  @cents %Schema{type: :integer, description: "Integer minor units (cents)"}
  @nullable_cents %Schema{type: :integer, nullable: true}
  @percent %Schema{type: :number, nullable: true}
  @uuid %Schema{type: :string, format: :uuid, nullable: true}

  def parameters do
    [
      %Parameter{
        name: :days,
        in: :query,
        required: false,
        description: "Gym-local days ending today (default 30; pricing 90)",
        schema: %Schema{type: :integer, minimum: 1, maximum: 366}
      },
      %Parameter{
        name: :from,
        in: :query,
        required: false,
        description: "First gym-local day (with `to`), ISO 8601",
        schema: %Schema{type: :string, format: :date}
      },
      %Parameter{
        name: :to,
        in: :query,
        required: false,
        description: "Last gym-local day (with `from`), ISO 8601",
        schema: %Schema{type: :string, format: :date}
      },
      PaleeWeb.Schemas.LocationScope.filter_parameter()
    ]
  end

  def limit_parameter do
    %Parameter{
      name: :limit,
      in: :query,
      required: false,
      description: "Rows per ranking (default 10)",
      schema: %Schema{type: :integer, minimum: 1, maximum: 50}
    }
  end

  defp window do
    %Schema{
      type: :object,
      required: [:from, :to, :time_zone],
      properties: %{
        from: %Schema{type: :string, format: :date},
        to: %Schema{type: :string, format: :date},
        time_zone: %Schema{type: :string, description: "The gym's zone the days follow"},
        location_ids: %Schema{type: :array, items: %Schema{type: :string}, nullable: true}
      }
    }
  end

  defp totals(extra \\ %{}) do
    %Schema{
      type: :object,
      required: [:gross_cents, :refunded_cents, :net_cents, :orders, :average_order_value_cents],
      properties:
        Map.merge(
          %{
            gross_cents: @cents,
            refunded_cents: @cents,
            net_cents: @cents,
            orders: %Schema{type: :integer},
            average_order_value_cents: @cents
          },
          extra
        )
    }
  end

  defp report(title, properties) do
    %Schema{
      title: title,
      type: :object,
      required: [:window | Map.keys(properties)],
      properties: Map.put(properties, :window, window()),
      additionalProperties: false
    }
  end

  defp array(items), do: %Schema{type: :array, items: items}

  def overview_response do
    report("ShopReportOverview", %{
      kpis:
        totals(%{
          units_sold: %Schema{type: :integer},
          units_per_order: %Schema{type: :number, nullable: true},
          refund_rate_percent: @percent,
          margin_cents: @cents,
          margin_percent: @percent,
          cost_coverage_percent: @percent,
          stock_on_hand: %Schema{type: :integer},
          stock_value_cents: @cents,
          low_stock_count: %Schema{type: :integer},
          sell_through_percent: @percent
        })
    })
  end

  def sales_response do
    report("ShopSalesReport", %{
      series: array(totals(%{day: %Schema{type: :string, format: :date}})),
      totals: totals()
    })
  end

  defp product_row do
    %Schema{
      type: :object,
      properties: %{
        product_id: @uuid,
        product_name: %Schema{type: :string, nullable: true},
        variant_id: @uuid,
        variant_name: %Schema{type: :string, nullable: true},
        units: %Schema{type: :integer},
        refunded_units: %Schema{type: :integer},
        net_units: %Schema{type: :integer},
        revenue_cents: @cents,
        refunded_cents: @cents,
        net_revenue_cents: @cents
      }
    }
  end

  def products_response do
    report("ShopProductsReport", %{
      products_by_revenue: array(product_row()),
      products_by_units: array(product_row()),
      variants_by_revenue: array(product_row()),
      variants_by_units: array(product_row())
    })
  end

  defp margin_totals(extra \\ %{}) do
    %Schema{
      type: :object,
      properties:
        Map.merge(
          %{
            net_revenue_cents: @cents,
            costed_revenue_cents: @cents,
            uncosted_revenue_cents: @cents,
            cost_cents: @cents,
            margin_cents: @cents,
            margin_percent: @percent,
            cost_coverage_percent: @percent
          },
          extra
        )
    }
  end

  def margin_response do
    report("ShopMarginReport", %{
      totals: margin_totals(),
      products:
        array(
          margin_totals(%{
            product_id: @uuid,
            product_name: %Schema{type: :string, nullable: true}
          })
        )
    })
  end

  def channels_response do
    report("ShopChannelsReport", %{
      by_channel:
        array(
          totals(%{
            channel: %Schema{
              type: :string,
              enum: ["online", "pos"],
              description: "online = online order for pickup; pos = desk"
            }
          })
        ),
      by_location: array(totals(%{location_id: @uuid}))
    })
  end

  defp stock_row do
    %Schema{
      type: :object,
      properties: %{
        variant_id: @uuid,
        product_id: @uuid,
        product_name: %Schema{type: :string, nullable: true},
        variant_name: %Schema{type: :string, nullable: true},
        location_id: @uuid,
        on_hand: %Schema{type: :integer},
        reserved: %Schema{type: :integer},
        available: %Schema{type: :integer},
        unit_cost_cents: @nullable_cents,
        stock_value_cents: @nullable_cents,
        low_stock_threshold: %Schema{type: :integer, nullable: true},
        low_stock: %Schema{type: :boolean},
        sold_units: %Schema{type: :integer},
        sell_through_percent: @percent
      }
    }
  end

  def inventory_response do
    report("ShopInventoryReport", %{
      totals: %Schema{
        type: :object,
        properties: %{
          on_hand: %Schema{type: :integer},
          reserved: %Schema{type: :integer},
          stock_value_cents: @cents,
          uncosted_variants: %Schema{type: :integer},
          low_stock_count: %Schema{type: :integer},
          sold_units: %Schema{type: :integer},
          sell_through_percent: @percent
        }
      },
      low_stock: array(stock_row()),
      items: array(stock_row())
    })
  end

  def attribution_response do
    report("ShopAttributionReport", %{
      by_promotion_code: array(totals(%{promotion_code: %Schema{type: :string}})),
      by_campaign: array(totals(%{campaign_id: @uuid})),
      by_source:
        array(
          totals(%{
            source: %Schema{
              type: :string,
              description: "club_post, promotion_code, desk, public_page or other"
            },
            source_ref_id: @uuid
          })
        ),
      attributed: totals(),
      unattributed: totals()
    })
  end

  def pricing_response do
    report("ShopPricingIndicators", %{
      window_days: %Schema{type: :integer},
      categories:
        array(%Schema{
          type: :object,
          properties: %{
            category: %Schema{type: :string},
            items: %Schema{type: :integer},
            min_cents: @cents,
            p25_cents: @cents,
            median_cents: @cents,
            p75_cents: @cents,
            max_cents: @cents,
            median_velocity_per_week: %Schema{type: :number, nullable: true},
            target_margin_bp: %Schema{type: :integer}
          }
        }),
      variants:
        array(%Schema{
          type: :object,
          description:
            "Per-variant pricing indicators. `suggested_price` is advisory and lists its inputs and reasoning.",
          additionalProperties: true,
          properties: %{
            variant_id: @uuid,
            product_id: @uuid,
            category: %Schema{type: :string},
            price_cents: @cents,
            cost_cents: @nullable_cents,
            margin_percent: @percent,
            markup_percent: @percent,
            velocity_per_week: %Schema{type: :number, nullable: true},
            sell_through_percent: @percent,
            days_of_stock_left: %Schema{type: :integer, nullable: true},
            price_changes: array(%Schema{type: :object, additionalProperties: true}),
            discount: %Schema{type: :object, additionalProperties: true},
            elasticity: %Schema{type: :object, additionalProperties: true},
            band: %Schema{type: :object, nullable: true, additionalProperties: true},
            suggested_price: %Schema{
              type: :object,
              additionalProperties: true,
              properties: %{
                advisory: %Schema{type: :boolean},
                low_cents: @nullable_cents,
                high_cents: @nullable_cents,
                inputs: %Schema{type: :object, additionalProperties: true},
                explanation: array(%Schema{type: :string})
              }
            }
          }
        })
    })
  end

  def pricing_targets_response do
    %Schema{
      title: "ShopPricingTargets",
      type: :object,
      required: [:targets],
      properties: %{
        targets:
          array(%Schema{
            type: :object,
            properties: %{
              category: %Schema{
                type: :string,
                nullable: true,
                description: "null = box-wide default"
              },
              target_margin_bp: %Schema{type: :integer, minimum: 0, maximum: 9500},
              implicit: %Schema{type: :boolean, description: "The built-in default, not yet set"}
            }
          })
      }
    }
  end

  def pricing_target_request do
    %Schema{
      title: "ShopPricingTargetRequest",
      type: :object,
      properties: %{
        category: %Schema{type: :string, nullable: true, maxLength: 80},
        target_margin_bp: %Schema{type: :integer, minimum: 0, maximum: 9500, nullable: true},
        target_margin_percent: %Schema{
          type: :string,
          nullable: true,
          description: "Alternative to basis points, e.g. \"37.5\""
        }
      }
    }
  end

  def reconciliation_response do
    %Schema{
      title: "ShopRevenueReconciliation",
      type: :object,
      required: [:ok, :days, :drifted, :drift_cents],
      properties: %{
        ok: %Schema{type: :boolean},
        from: %Schema{type: :string, format: :date},
        to: %Schema{type: :string, format: :date},
        time_zone: %Schema{type: :string},
        drift_cents: @cents,
        days: array(reconciliation_day()),
        drifted: array(reconciliation_day())
      }
    }
  end

  defp reconciliation_day do
    %Schema{
      type: :object,
      properties: %{
        day: %Schema{type: :string, format: :date},
        currency: %Schema{type: :string},
        orders_cents: @cents,
        invoice_lines_cents: @cents,
        payments_cents: @cents,
        ok: %Schema{type: :boolean},
        drift_cents: @cents,
        orders_vs_lines_cents: @cents,
        lines_vs_payments_cents: @cents
      }
    }
  end
end
