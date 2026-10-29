defmodule PaleeWeb.Schemas.Fiscal do
  @moduledoc "OpenAPI schemas of the Fiscal context (ADR-240–242)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @date %Schema{type: :string, format: :date}
  @time %Schema{type: :string, format: :"date-time"}
  @text %Schema{type: :string, nullable: true, maxLength: 200}

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def one(key, schema), do: %Schema{type: :object, properties: %{key => schema}, required: [key]}

  def profile do
    %Schema{
      type: :object,
      properties: %{
        country: %Schema{type: :string, minLength: 2, maxLength: 2},
        currency: %Schema{type: :string},
        languages: %Schema{type: :array, items: %Schema{type: :string}},
        tax_system: %Schema{type: :string, enum: ["vat", "sales_tax"]},
        authority: %Schema{type: :string, enum: ["mydata", "none"]},
        register: %Schema{type: :string, enum: ["nf525", "standard"]},
        till_device: %Schema{type: :string, enum: ["tse", "rksv", "none"]},
        einvoicing: %Schema{type: :array, items: %Schema{type: :string}},
        required_fields: %Schema{type: :array, items: %Schema{type: :string}},
        tax_office: %Schema{type: :boolean},
        retention_years: %Schema{type: :integer},
        tax_categories: %Schema{type: :array, items: %Schema{type: :string}}
      },
      required: [
        :authority,
        :country,
        :currency,
        :einvoicing,
        :languages,
        :register,
        :required_fields,
        :retention_years,
        :tax_categories,
        :tax_office,
        :tax_system,
        :till_device
      ]
    }
  end

  def countries do
    %Schema{
      type: :object,
      properties: %{
        countries: %Schema{type: :array, items: profile()},
        vat_schemes: %Schema{type: :array, items: %Schema{type: :string}}
      },
      required: [:countries, :vat_schemes]
    }
  end

  @identity_text ~w(legal_name trade_name tax_id vat_number tax_office registration_number
                    activity_code street building_number postal_code city region email phone
                    document_language)a

  def identity do
    %Schema{
      type: :object,
      nullable: true,
      properties:
        @identity_text
        |> Map.new(&{&1, @text})
        |> Map.merge(%{
          id: @uuid,
          country_code: %Schema{type: :string},
          vat_scheme: %Schema{type: :string, enum: ["standard", "small_business", "exempt"]},
          currency: %Schema{type: :string},
          branch_code: %Schema{type: :integer},
          fiscal_year_start_month: %Schema{type: :integer},
          updated_at: @time
        }),
      required: [
        :branch_code,
        :country_code,
        :currency,
        :fiscal_year_start_month,
        :id,
        :vat_scheme
      ]
    }
  end

  def identity_status do
    %Schema{
      type: :object,
      properties: %{
        identity: identity(),
        profile: %Schema{profile() | nullable: true},
        missing: %Schema{type: :array, items: %Schema{type: :string}},
        complete: %Schema{type: :boolean}
      },
      required: [:complete, :identity, :missing, :profile]
    }
  end

  def identity_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties:
        @identity_text
        |> Map.new(&{&1, @text})
        |> Map.merge(%{
          country_code: %Schema{type: :string, minLength: 2, maxLength: 2},
          vat_scheme: %Schema{type: :string, enum: ["standard", "small_business", "exempt"]},
          branch_code: %Schema{type: :integer, minimum: 0, maximum: 9999},
          fiscal_year_start_month: %Schema{type: :integer, minimum: 1, maximum: 12}
        })
    }
  end

  def tax_group do
    %Schema{
      type: :object,
      properties: %{
        tax_category: %Schema{type: :string},
        rate_bp: %Schema{type: :integer},
        net_cents: %Schema{type: :integer},
        tax_cents: %Schema{type: :integer},
        gross_cents: %Schema{type: :integer}
      },
      required: [:gross_cents, :net_cents, :rate_bp, :tax_category, :tax_cents]
    }
  end

  def line do
    %Schema{
      type: :object,
      properties: %{
        position: %Schema{type: :integer},
        description: %Schema{type: :string},
        quantity: %Schema{type: :integer},
        unit_price_cents: %Schema{type: :integer},
        discount_cents: %Schema{type: :integer},
        amount_cents: %Schema{type: :integer},
        tax_category: %Schema{type: :string},
        rate_bp: %Schema{type: :integer},
        exemption_reason: %Schema{type: :string, nullable: true},
        net_cents: %Schema{type: :integer},
        tax_cents: %Schema{type: :integer},
        gross_cents: %Schema{type: :integer},
        corrects_position: %Schema{type: :integer, nullable: true}
      },
      required: [
        :amount_cents,
        :description,
        :discount_cents,
        :gross_cents,
        :net_cents,
        :position,
        :quantity,
        :rate_bp,
        :tax_category,
        :tax_cents,
        :unit_price_cents
      ]
    }
  end

  def document do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        kind: %Schema{type: :string, enum: ["receipt", "invoice", "credit_note"]},
        series: %Schema{type: :string},
        sequence: %Schema{type: :integer},
        number: %Schema{type: :string},
        issue_date: @date,
        issued_at: @time,
        currency: %Schema{type: :string},
        prices_include_tax: %Schema{type: :boolean},
        country_code: %Schema{type: :string},
        language: %Schema{type: :string},
        seller: %Schema{type: :object, additionalProperties: true},
        buyer: %Schema{type: :object, nullable: true, additionalProperties: true},
        payment_method: %Schema{type: :string, nullable: true},
        net_cents: %Schema{type: :integer},
        tax_cents: %Schema{type: :integer},
        gross_cents: %Schema{type: :integer},
        tax_breakdown: %Schema{type: :array, items: tax_group()},
        corrects_document_id: %Schema{@uuid | nullable: true},
        source_type: %Schema{type: :string, nullable: true},
        source_id: %Schema{@uuid | nullable: true},
        content_hash: %Schema{type: :string},
        journal_position: %Schema{type: :integer},
        lines: %Schema{type: :array, items: line()}
      },
      required: [
        :content_hash,
        :country_code,
        :currency,
        :gross_cents,
        :id,
        :issue_date,
        :issued_at,
        :journal_position,
        :kind,
        :language,
        :net_cents,
        :number,
        :prices_include_tax,
        :seller,
        :sequence,
        :series,
        :tax_breakdown,
        :tax_cents
      ]
    }
  end

  def document_detail do
    %Schema{
      document()
      | properties:
          Map.put(document().properties, :credit_notes, %Schema{type: :array, items: document()})
    }
  end

  def document_page do
    %Schema{
      type: :object,
      properties: %{
        documents: %Schema{type: :array, items: document()},
        total: %Schema{type: :integer}
      },
      required: [:documents, :total]
    }
  end

  def credit_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 120},
        lines: %Schema{
          type: :array,
          maxItems: 200,
          items: %Schema{
            type: :object,
            properties: %{
              position: %Schema{type: :integer, minimum: 1},
              quantity: %Schema{type: :integer, minimum: 1}
            },
            required: [:position, :quantity]
          }
        }
      },
      required: [:idempotency_key]
    }
  end

  def verification do
    %Schema{
      type: :object,
      properties: %{
        valid: %Schema{type: :boolean},
        entries: %Schema{type: :integer},
        head: %Schema{type: :string},
        broken_at: %Schema{type: :integer},
        reason: %Schema{type: :string}
      },
      required: [:entries, :valid]
    }
  end

  def closing do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        period_kind: %Schema{type: :string, enum: ["day", "month", "year"]},
        period_start: @date,
        period_end: @date,
        totals: %Schema{type: :object, additionalProperties: true},
        journal_position: %Schema{type: :integer},
        closed_at: @time
      },
      required: [
        :closed_at,
        :id,
        :journal_position,
        :period_end,
        :period_kind,
        :period_start,
        :totals
      ]
    }
  end
end
