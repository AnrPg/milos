defmodule PaleeWeb.Schemas.FiscalRegistry do
  @moduledoc "OpenAPI schemas of «Συμπλήρωση από το ΑΦΜ», AADE's registry (ADR-265)."

  alias OpenApiSpex.Schema

  @nullable_text %Schema{type: :string, nullable: true}

  def connection do
    PaleeWeb.Schemas.FiscalConnections.with_check(%Schema{
      type: :object,
      nullable: true,
      description:
        "The AADE registry connection; the password is never returned. `username` is the " <>
          "same field the save takes (ADR-273).",
      properties: %{
        environment: %Schema{type: :string, enum: ["sandbox", "production"]},
        username: @nullable_text,
        status: %Schema{type: :string, enum: ["active", "invalid"]},
        has_password: %Schema{type: :boolean},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:environment, :has_password, :status, :updated_by_platform]
    })
  end

  def connection_status do
    %Schema{
      type: :object,
      properties: %{connection: connection()},
      required: [:connection]
    }
  end

  def connection_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        environment: %Schema{type: :string, enum: ["sandbox", "production"]},
        username: %Schema{type: :string, maxLength: 100},
        password: %Schema{type: :string, maxLength: 200, format: :password}
      },
      required: [:environment]
    }
  end

  def activity do
    %Schema{
      type: :object,
      properties: %{
        code: %Schema{type: :string},
        description: @nullable_text,
        main: %Schema{type: :boolean}
      },
      required: [:code, :main]
    }
  end

  def business do
    %Schema{
      type: :object,
      properties: %{
        business: %Schema{
          type: :object,
          properties: %{
            tax_id: %Schema{type: :string},
            legal_name: @nullable_text,
            trade_name: @nullable_text,
            tax_office: @nullable_text,
            tax_office_code: @nullable_text,
            street: @nullable_text,
            building_number: @nullable_text,
            postal_code: @nullable_text,
            city: @nullable_text,
            activity_code: @nullable_text,
            activity_description: @nullable_text,
            activities: %Schema{type: :array, items: activity()},
            active: %Schema{type: :boolean},
            legal_status: @nullable_text,
            vat_registered: %Schema{type: :boolean}
          },
          required: [:active, :activities, :tax_id, :vat_registered]
        }
      },
      required: [:business]
    }
  end
end
