defmodule PaleeWeb.Schemas.FiscalTax do
  @moduledoc "OpenAPI schemas of fiscal taxes, document files and accounting exports (ADR-244, ADR-245)."

  alias OpenApiSpex.Schema

  @time %Schema{type: :string, format: :"date-time"}

  def tax_categories do
    %Schema{
      type: :object,
      properties: %{
        country: %Schema{type: :string, nullable: true},
        categories: %Schema{type: :array, items: %Schema{type: :string}},
        default: %Schema{type: :string},
        max_exemption_reason: %Schema{type: :integer}
      },
      required: [:categories, :country, :default, :max_exemption_reason]
    }
  end

  def sales_tax_rate do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        state: %Schema{type: :string, minLength: 2, maxLength: 2},
        zip: %Schema{type: :string, nullable: true, minLength: 5, maxLength: 5},
        rate_bp: %Schema{type: :integer, minimum: 0, maximum: 9999},
        label: %Schema{type: :string, nullable: true},
        updated_at: Map.put(@time, :nullable, true)
      },
      required: [:label, :rate_bp, :state, :zip]
    }
  end

  def sales_tax_rates do
    %Schema{
      type: :object,
      properties: %{
        applies: %Schema{type: :boolean},
        rates: %Schema{type: :array, items: sales_tax_rate()},
        states: %Schema{type: :array, items: %Schema{type: :string}}
      },
      required: [:applies, :rates, :states]
    }
  end

  def sales_tax_rates_body do
    %Schema{
      type: :object,
      properties: %{
        rates: %Schema{
          type: :array,
          maxItems: 2000,
          items: %Schema{
            type: :object,
            properties: %{
              state: %Schema{type: :string, minLength: 2, maxLength: 2},
              zip: %Schema{type: :string, nullable: true, maxLength: 5},
              rate_bp: %Schema{type: :integer},
              label: %Schema{type: :string, nullable: true}
            },
            required: [:rate_bp, :state]
          }
        }
      },
      required: [:rates]
    }
  end

  def export_option do
    %Schema{
      type: :object,
      properties: %{
        key: %Schema{type: :string},
        type: %Schema{type: :string, enum: ["string", "integer", "boolean", "enum", "map"]},
        default: %Schema{nullable: true},
        values: %Schema{type: :array, items: %Schema{type: :string}},
        description: %Schema{type: :string}
      },
      required: [:default, :description, :key, :type]
    }
  end

  def export_format do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string},
        name: %Schema{type: :string},
        description: %Schema{type: :string},
        file_extension: %Schema{type: :string},
        file_prefix: %Schema{type: :string},
        content_type: %Schema{type: :string},
        options: %Schema{type: :array, items: export_option()}
      },
      required: [:content_type, :description, :file_extension, :file_prefix, :id, :name, :options]
    }
  end

  def export_setting do
    %Schema{
      type: :object,
      properties: %{
        format: %Schema{type: :string},
        name: %Schema{type: :string},
        options: %Schema{type: :object, additionalProperties: true},
        saved: %Schema{type: :boolean},
        updated_at: Map.put(@time, :nullable, true)
      },
      required: [:format, :name, :options, :saved, :updated_at]
    }
  end

  def export_formats do
    %Schema{
      type: :object,
      properties: %{
        formats: %Schema{type: :array, items: export_format()},
        settings: %Schema{type: :array, items: export_setting()}
      },
      required: [:formats, :settings]
    }
  end

  def export_settings_body do
    %Schema{
      type: :object,
      properties: %{options: %Schema{type: :object, additionalProperties: true}},
      required: [:options]
    }
  end
end
