defmodule MilosTrainingWeb.Schemas.Widgets do
  @moduledoc "OpenAPI shapes of the home-screen widgets (ADR-173)."

  alias MilosTrainingWeb.Schemas.Community
  alias OpenApiSpex.Schema

  @datetime %Schema{type: :string, format: :"date-time"}
  @maybe_string %Schema{type: :string, nullable: true}

  def body(schema), do: Community.body(schema)
  def error, do: %Schema{type: :object, additionalProperties: true}

  def token_request do
    %Schema{
      title: "WidgetTokenRequest",
      type: :object,
      properties: %{
        platform: %Schema{type: :string, enum: ~w(ios android)},
        replaces_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "This install's previous token, revoked when the new one is issued"
        }
      },
      required: [:platform]
    }
  end

  def token_response do
    %Schema{
      title: "WidgetToken",
      type: :object,
      description: "A token only the widget endpoints accept; the app stores it for its widgets",
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        token: %Schema{type: :string},
        expires_at: @datetime
      },
      required: [:id, :token, :expires_at]
    }
  end

  def water_request do
    %Schema{
      title: "WidgetWaterRequest",
      type: :object,
      properties: %{timezone: %Schema{type: :string, description: "The phone's IANA zone"}}
    }
  end

  defp item do
    %Schema{
      type: :object,
      properties: %{
        kind: %Schema{type: :string, enum: ~w(class appointment program wod)},
        title: @maybe_string,
        at: %Schema{type: :string, format: :"date-time", nullable: true},
        status: @maybe_string,
        box_name: @maybe_string
      },
      required: [:kind]
    }
  end

  def snapshot_response do
    %Schema{
      title: "WidgetSnapshot",
      type: :object,
      description:
        "What the three widgets show: water today (null when hidden), the first items of «Σήμερα» and the next booked class",
      properties: %{
        water: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            ml: %Schema{type: :integer},
            goal_ml: %Schema{type: :integer},
            glass_ml: %Schema{type: :integer},
            count: %Schema{type: :integer},
            status: %Schema{type: :string, enum: ~w(none partial full)},
            can_add: %Schema{
              type: :boolean,
              description: "False until the health-data consent is given in the app"
            }
          },
          required: [:ml, :goal_ml, :glass_ml, :count, :status, :can_add]
        },
        today: %Schema{type: :array, items: item()},
        next_class: %Schema{item() | nullable: true},
        generated_at: @datetime
      },
      required: [:water, :today, :next_class, :generated_at]
    }
  end
end
