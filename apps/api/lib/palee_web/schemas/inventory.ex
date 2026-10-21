defmodule PaleeWeb.Schemas.Inventory do
  @moduledoc "OpenAPI schemas for the gym's inventory (ADR-104)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @time %Schema{type: :string, format: :"date-time", nullable: true}
  @date %Schema{type: :string, format: :date, nullable: true}
  @text %Schema{type: :string, nullable: true}
  @cents %Schema{type: :integer, minimum: 0, nullable: true}

  def uuid, do: @uuid

  def machine do
    %Schema{
      title: "InventoryMachine",
      type: :object,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        category: %Schema{type: :string, enum: ["training", "appliance"]},
        brand: @text,
        model: @text,
        serial_number: @text,
        location_id: %Schema{type: :string, format: :uuid, nullable: true},
        quantity: %Schema{type: :integer},
        purchased_on: @date,
        purchase_price_cents: @cents,
        warranty_until: @date,
        service_contact: @text,
        service_interval_days: %Schema{type: :integer, nullable: true},
        last_serviced_on: @date,
        next_service_on: @date,
        service_due: %Schema{type: :boolean},
        status: %Schema{
          type: :string,
          enum: ["working", "needs_attention", "out_of_order", "retired"]
        },
        notes: @text,
        archived_at: @time
      },
      required: [:id, :name, :category, :quantity, :status]
    }
  end

  def machine_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        name: %Schema{type: :string, minLength: 1, maxLength: 120},
        category: %Schema{type: :string, enum: ["training", "appliance"]},
        brand: %Schema{type: :string, maxLength: 120, nullable: true},
        model: %Schema{type: :string, maxLength: 120, nullable: true},
        serial_number: %Schema{type: :string, maxLength: 120, nullable: true},
        location_id: %Schema{type: :string, format: :uuid, nullable: true},
        quantity: %Schema{type: :integer, minimum: 1},
        purchased_on: @date,
        purchase_price_cents: @cents,
        warranty_until: @date,
        service_contact: %Schema{type: :string, maxLength: 1000, nullable: true},
        service_interval_days: %Schema{type: :integer, minimum: 1, nullable: true},
        last_serviced_on: @date,
        notes: %Schema{type: :string, maxLength: 4000, nullable: true}
      }
    }
  end

  @severities ["low", "medium", "high", "safety"]
  @symptoms [
    "noise",
    "not_starting",
    "broken_part",
    "leak",
    "electrical",
    "display",
    "cleanliness",
    "other"
  ]

  @kinds [
    "note",
    "issue",
    "out_of_order",
    "repair_requested",
    "maintenance",
    "repaired",
    "retired"
  ]

  def machine_event do
    %Schema{
      title: "InventoryMachineEvent",
      type: :object,
      properties: %{
        id: @uuid,
        machine_id: @uuid,
        user_id: %Schema{type: :string, format: :uuid, nullable: true},
        nickname: @text,
        kind: %Schema{type: :string, enum: @kinds},
        severity: %Schema{type: :string, enum: @severities, nullable: true},
        symptom: %Schema{type: :string, enum: @symptoms, nullable: true},
        usable: %Schema{type: :boolean, nullable: true},
        body: @text,
        cost_cents: @cents,
        occurred_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :machine_id, :kind, :occurred_at]
    }
  end

  def machine_event_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        kind: %Schema{type: :string, enum: @kinds},
        severity: %Schema{type: :string, enum: @severities, nullable: true},
        symptom: %Schema{type: :string, enum: @symptoms, nullable: true},
        usable: %Schema{type: :boolean, nullable: true},
        body: %Schema{type: :string, maxLength: 4000, nullable: true},
        cost_cents: @cents,
        occurred_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:kind]
    }
  end

  def stock do
    %Schema{
      type: :object,
      properties: %{
        status: %Schema{type: :string, enum: ["ok", "low", "critical", "out"]},
        days_left: %Schema{type: :number, nullable: true},
        daily_use: %Schema{type: :number},
        basis: %Schema{type: :string, enum: ["observed", "estimated"]}
      },
      required: [:status, :daily_use, :basis]
    }
  end

  def supply do
    %Schema{
      title: "InventorySupply",
      type: :object,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        description: @text,
        brand: @text,
        shop: @text,
        url: @text,
        unit: @text,
        unit_price_cents: @cents,
        quantity: %Schema{type: :integer},
        consumption_speed: %Schema{type: :string, enum: ["fast", "regular", "slow"]},
        reorder_level: %Schema{type: :integer, nullable: true},
        stock_status: %Schema{type: :string, enum: ["ok", "low", "critical", "out"]},
        stock: stock(),
        open_reports: %Schema{type: :array, items: low_report()},
        archived_at: @time
      },
      required: [:id, :name, :quantity, :consumption_speed, :stock_status]
    }
  end

  def supply_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        name: %Schema{type: :string, minLength: 1, maxLength: 120},
        description: %Schema{type: :string, maxLength: 2000, nullable: true},
        brand: %Schema{type: :string, maxLength: 120, nullable: true},
        shop: %Schema{type: :string, maxLength: 200, nullable: true},
        url: %Schema{type: :string, maxLength: 2048, nullable: true},
        unit: %Schema{type: :string, maxLength: 40, nullable: true},
        unit_price_cents: @cents,
        quantity: %Schema{type: :integer, minimum: 0, description: "Starting count (create only)"},
        consumption_speed: %Schema{type: :string, enum: ["fast", "regular", "slow"]},
        reorder_level: %Schema{type: :integer, minimum: 0, nullable: true}
      }
    }
  end

  def low_report do
    %Schema{
      title: "InventoryLowReport",
      type: :object,
      properties: %{
        id: @uuid,
        supply_id: @uuid,
        user_id: %Schema{type: :string, format: :uuid, nullable: true},
        nickname: @text,
        level: %Schema{type: :string, enum: ["running_low", "empty"]},
        seen_quantity: %Schema{type: :integer, nullable: true},
        place: @text,
        note: @text,
        reported_at: %Schema{type: :string, format: :"date-time"},
        resolved_at: @time,
        resolved_by_id: %Schema{type: :string, format: :uuid, nullable: true},
        resolved_by: @text
      },
      required: [:id, :supply_id, :level, :reported_at]
    }
  end

  def low_report_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        level: %Schema{type: :string, enum: ["running_low", "empty"]},
        seen_quantity: %Schema{type: :integer, minimum: 0, nullable: true},
        place: %Schema{type: :string, maxLength: 120, nullable: true},
        note: %Schema{type: :string, maxLength: 1000, nullable: true}
      }
    }
  end

  def movement do
    %Schema{
      title: "InventorySupplyMovement",
      type: :object,
      properties: %{
        id: @uuid,
        supply_id: @uuid,
        user_id: %Schema{type: :string, format: :uuid, nullable: true},
        nickname: @text,
        kind: %Schema{type: :string, enum: ["restock", "consume", "adjust"]},
        quantity: %Schema{type: :integer},
        unit_price_cents: @cents,
        total_cents: @cents,
        note: @text,
        occurred_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :supply_id, :kind, :quantity, :occurred_at]
    }
  end

  def movement_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        kind: %Schema{type: :string, enum: ["restock", "consume", "adjust"]},
        quantity: %Schema{
          type: :integer,
          minimum: 0,
          description: "Amount restocked or used; for adjust, the new count"
        },
        unit_price_cents: @cents,
        total_cents: @cents,
        note: %Schema{type: :string, maxLength: 1000, nullable: true},
        occurred_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:kind, :quantity]
    }
  end

  def report do
    month = %Schema{
      type: :object,
      properties: %{
        month: %Schema{type: :string},
        supplies_cents: %Schema{type: :integer},
        machines_cents: %Schema{type: :integer},
        total_cents: %Schema{type: :integer}
      },
      required: [:month, :supplies_cents, :machines_cents, :total_cents]
    }

    item = %Schema{
      type: :object,
      properties: %{
        supply_id: @uuid,
        name: %Schema{type: :string},
        unit: @text,
        consumed: %Schema{type: :integer},
        consumed_per_month: %Schema{type: :number},
        purchased: %Schema{type: :integer},
        spent_cents: %Schema{type: :integer},
        spent_per_month_cents: %Schema{type: :integer},
        monthly: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{month: %Schema{type: :string}, cents: %Schema{type: :integer}},
            required: [:month, :cents]
          }
        }
      },
      required: [:supply_id, :name, :consumed, :consumed_per_month, :spent_cents, :monthly]
    }

    %Schema{
      title: "InventoryReport",
      type: :object,
      properties: %{
        from: %Schema{type: :string, format: :date},
        to: %Schema{type: :string, format: :date},
        supplies: %Schema{type: :array, items: item},
        expenses: %Schema{type: :array, items: month},
        totals: %Schema{
          type: :object,
          properties: %{
            supplies_cents: %Schema{type: :integer},
            machines_cents: %Schema{type: :integer}
          },
          required: [:supplies_cents, :machines_cents]
        }
      },
      required: [:from, :to, :supplies, :expenses, :totals]
    }
  end

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def one(key, schema), do: %Schema{type: :object, properties: %{key => schema}, required: [key]}
  def many(key, schema), do: one(key, %Schema{type: :array, items: schema})
end
