defmodule PaleeWeb.Schemas.FiscalConnections do
  @moduledoc "OpenAPI schemas of a box's fiscal connections as one set and «Δοκιμή σύνδεσης» (ADR-273)."

  alias OpenApiSpex.Schema
  alias Palee.Fiscal.Domain.ConnectionCheckPolicy
  alias PaleeWeb.Schemas.Fiscal, as: F
  alias PaleeWeb.Schemas.FiscalCompliance, as: C
  alias PaleeWeb.Schemas.FiscalRegistry, as: R

  @time %Schema{type: :string, format: :"date-time"}

  def kinds, do: ConnectionCheckPolicy.kinds()

  def error_code do
    %Schema{
      type: :string,
      nullable: true,
      enum: ConnectionCheckPolicy.error_codes(),
      description:
        "Why the last check (or the provider, while working) refused the connection; " <>
          "screens turn it into a plain message. Provider text is never returned."
    }
  end

  @doc "The properties every connection carries about its last check (merged into each schema)."
  def check_properties do
    %{
      error_code: error_code(),
      checked_at: %Schema{@time | nullable: true},
      updated_by_id: %Schema{type: :string, format: :uuid, nullable: true},
      updated_by_platform: %Schema{
        type: :boolean,
        description: "Saved last by the Palee team from the vendor console."
      },
      updated_by_name: %Schema{
        type: :string,
        nullable: true,
        description: "Who saved it last (the connections overview only; nil for the Palee team)."
      }
    }
  end

  @doc "Adds the check properties to a connection schema."
  def with_check(%Schema{properties: properties} = schema),
    do: %Schema{schema | properties: Map.merge(properties, check_properties())}

  def check do
    %Schema{
      type: :object,
      description: "The result of «Δοκιμή σύνδεσης».",
      properties: %{
        result: %Schema{
          type: :string,
          enum: ["ok", "invalid", "unreachable"],
          description:
            "`invalid`: refused (the connection is marked invalid); `unreachable`: the " <>
              "provider could not be asked, nothing changed and it is checked again soon."
        },
        error_code: error_code(),
        detail: %Schema{
          type: :object,
          properties: %{
            tax_id: %Schema{type: :string, description: "Registry: the ΑΦΜ looked up."},
            legal_name: %Schema{
              type: :string,
              nullable: true,
              description: "Registry: the name AADE has for it."
            }
          }
        }
      },
      required: [:detail, :error_code, :result]
    }
  end

  @doc "What a save or a check answers: the connection after its check, and the check."
  def result(connection_schema) do
    %Schema{
      type: :object,
      properties: %{
        connection: %Schema{connection_schema | nullable: true},
        check: %Schema{check() | nullable: true}
      },
      required: [:check, :connection]
    }
  end

  def any_result do
    %Schema{
      type: :object,
      properties: %{
        connection: %Schema{
          oneOf: [F.connection(), R.connection(), C.till_connection(), C.peppol_connection()],
          nullable: true
        },
        check: %Schema{check() | nullable: true}
      },
      required: [:check, :connection]
    }
  end

  def overview do
    nullable = fn schema -> %Schema{schema | nullable: true} end

    %Schema{
      type: :object,
      description:
        "The connections the box's country asks for (`kinds`, in screen order; none before " <>
          "a country is chosen), each as saved (nil when not yet), and who manages them.",
      properties: %{
        country: %Schema{type: :string, nullable: true},
        kinds: %Schema{type: :array, items: %Schema{type: :string, enum: kinds()}},
        managed_by: %Schema{
          type: :string,
          enum: ["owner", "palee"],
          description: "`palee`: the Palee team manages them; staff see them but cannot save."
        },
        connections: %Schema{
          type: :object,
          properties: %{
            mydata: nullable.(F.connection()),
            registry: nullable.(R.connection()),
            tse: nullable.(C.till_connection()),
            rksv: nullable.(C.till_connection()),
            sign_fr: nullable.(C.till_connection()),
            peppol: nullable.(C.peppol_connection())
          }
        }
      },
      required: [:connections, :country, :kinds, :managed_by]
    }
  end

  def managed_by_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{managed_by: %Schema{type: :string, enum: ["owner", "palee"]}},
      required: [:managed_by]
    }
  end

  @doc "The vendor console's save: the fields of the owner's form for that kind."
  def platform_save_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      description:
        "The same fields the box's own form sends for this connection (myDATA: " <>
          "`environment`, `user_id`, `subscription_key`; registry: `environment`, `username`, " <>
          "`password`; till devices: `environment`, `api_key`, `api_secret`, `reprovision`; " <>
          "Peppol: `environment`, `legal_entity_id`, `peppol_id`, `api_key`, `api_secret`).",
      properties: %{
        environment: %Schema{type: :string, enum: ["sandbox", "test", "production"]},
        user_id: %Schema{type: :string, nullable: true, maxLength: 100},
        subscription_key: %Schema{type: :string, nullable: true, maxLength: 200},
        username: %Schema{type: :string, maxLength: 100},
        password: %Schema{type: :string, maxLength: 200, format: :password},
        api_key: %Schema{type: :string, nullable: true, maxLength: 500},
        api_secret: %Schema{type: :string, nullable: true, maxLength: 500},
        reprovision: %Schema{type: :boolean},
        legal_entity_id: %Schema{type: :string, nullable: true, maxLength: 40},
        peppol_id: %Schema{type: :string, nullable: true, maxLength: 60}
      },
      required: [:environment]
    }
  end
end
