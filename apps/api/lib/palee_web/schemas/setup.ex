defmodule PaleeWeb.Schemas.Setup do
  @moduledoc "OpenAPI schemas of the Setup context (ADR-255): settings catalog and setup recipes."

  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @time %Schema{type: :string, format: :"date-time"}
  @names %Schema{
    type: :object,
    description: "The same text in English and Greek",
    properties: %{en: %Schema{type: :string}, el: %Schema{type: :string}},
    required: [:el, :en]
  }
  @any %Schema{
    nullable: true,
    description: "A setting value: boolean, number, text, list or null"
  }
  @verdict %Schema{type: :string, enum: ["advanced", "basic", "derive", "remove"]}
  @grants %Schema{
    type: :object,
    additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}
  }

  def setting do
    %Schema{
      type: :object,
      description:
        "A business setting with its CP-H1 verdict. `advanced` settings stay under «Προχωρημένα», closed by default.",
      properties: %{
        key: %Schema{type: :string, description: "`<section>.<field>`"},
        section: %Schema{type: :string},
        field: %Schema{type: :string},
        verdict: @verdict,
        advanced: %Schema{type: :boolean},
        default: @any,
        set_by_recipe: %Schema{type: :boolean}
      },
      required: [:advanced, :default, :field, :key, :section, :set_by_recipe, :verdict]
    }
  end

  def settings_catalog do
    %Schema{
      type: :object,
      properties: %{
        settings: %Schema{type: :array, items: setting()},
        counts: %Schema{
          type: :object,
          properties: %{
            advanced: %Schema{type: :integer},
            basic: %Schema{type: :integer},
            derive: %Schema{type: :integer},
            remove: %Schema{type: :integer}
          },
          required: [:advanced, :basic, :derive, :remove]
        },
        advanced_settings: %Schema{type: :array, items: %Schema{type: :string}}
      },
      required: [:advanced_settings, :counts, :settings]
    }
  end

  def recipe do
    %Schema{
      type: :object,
      description: "A setup recipe: starting choices for one kind of box (CP-H2)",
      properties: %{
        key: %Schema{type: :string},
        version: %Schema{type: :integer},
        name: %Schema{type: :string, description: "In the business's language"},
        summary: %Schema{type: :string},
        names: @names,
        summaries: @names,
        provider_kind: %Schema{type: :string, enum: ["coach", "gym", "organiser"]},
        settings: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              key: %Schema{type: :string},
              value: @any,
              advanced: %Schema{type: :boolean}
            },
            required: [:advanced, :key, :value]
          }
        },
        class_types: %Schema{type: :array, items: %Schema{type: :string}},
        packages: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              code: %Schema{type: :string},
              name: %Schema{type: :string},
              package_type: %Schema{type: :string},
              billing_period: %Schema{type: :string},
              base_price_cents: %Schema{type: :integer, minimum: 0}
            },
            required: [:base_price_cents, :billing_period, :code, :name, :package_type]
          }
        },
        role_grants: @grants,
        documents: %Schema{type: :array, items: %Schema{type: :string}}
      },
      required: [
        :class_types,
        :documents,
        :key,
        :name,
        :names,
        :packages,
        :provider_kind,
        :role_grants,
        :settings,
        :summaries,
        :summary,
        :version
      ]
    }
  end

  def change do
    %Schema{
      type: :object,
      description:
        "One step of a plan. `area`: provider, package, class_type, setting, role_grant or document; " <>
          "`action`: set, create, add or manual (to do by hand).",
      properties: %{
        area: %Schema{
          type: :string,
          enum: ["class_type", "document", "package", "provider", "role_grant", "setting"]
        },
        key: %Schema{type: :string},
        action: %Schema{type: :string, enum: ["add", "create", "manual", "set"]},
        from: @any,
        to: @any,
        name: %Schema{type: :string, nullable: true},
        advanced: %Schema{type: :boolean}
      },
      required: [:action, :advanced, :area, :from, :key, :name, :to]
    }
  end

  def plan do
    %Schema{
      type: :object,
      description: "What applying the recipe changes now (a dry run until applied)",
      properties: %{
        recipe: %Schema{type: :string},
        version: %Schema{type: :integer},
        name: %Schema{type: :string},
        changes: %Schema{type: :array, items: change()},
        manual: %Schema{type: :array, items: change()},
        unchanged: %Schema{type: :array, items: %Schema{type: :string}},
        change_count: %Schema{type: :integer, minimum: 0}
      },
      required: [:change_count, :changes, :manual, :name, :recipe, :unchanged, :version]
    }
  end

  def application do
    %Schema{
      type: :object,
      description: "An applied recipe: which, when, by whom and what changed",
      properties: %{
        id: @uuid,
        recipe_key: %Schema{type: :string},
        recipe_version: %Schema{type: :integer},
        applied_by_id: %Schema{type: :string, format: :uuid, nullable: true},
        applied_at: @time,
        changes: %Schema{type: :array, items: change()},
        manual: %Schema{type: :array, items: change()},
        change_count: %Schema{type: :integer, minimum: 0}
      },
      required: [
        :applied_at,
        :applied_by_id,
        :change_count,
        :changes,
        :id,
        :manual,
        :recipe_key,
        :recipe_version
      ]
    }
  end

  def recipes do
    %Schema{
      type: :object,
      properties: %{
        recipes: %Schema{type: :array, items: recipe()},
        applications: %Schema{type: :array, items: application()},
        can_apply: %Schema{type: :boolean, description: "Only the owner applies a recipe"},
        currency: %Schema{type: :string, description: "ISO currency of the suggested prices"}
      },
      required: [:applications, :can_apply, :currency, :recipes]
    }
  end

  def apply_body do
    %OpenApiSpex.RequestBody{
      required: false,
      content: %{
        "application/json" => %OpenApiSpex.MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              prices: %Schema{
                type: :object,
                description:
                  "The owner's prices for the recipe's packages: package code => cents",
                additionalProperties: %Schema{type: :integer, minimum: 0, maximum: 10_000_000}
              }
            }
          }
        }
      }
    }
  end

  def applied do
    %Schema{
      type: :object,
      properties: %{plan: plan(), application: application()},
      required: [:application, :plan]
    }
  end
end
