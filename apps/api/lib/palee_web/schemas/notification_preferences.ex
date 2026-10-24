defmodule PaleeWeb.Schemas.NotificationPreferences do
  @moduledoc "OpenAPI schemas of per-category notification choices (ADR-199)."

  alias OpenApiSpex.Schema
  alias Palee.Notifications

  def category,
    do: %Schema{
      type: :string,
      enum: Notifications.notification_categories(),
      description: "A notification category, in the order the switches are shown."
    }

  defp channels do
    %Schema{
      type: :object,
      description:
        "Whether the category reaches the person on each channel it has: `in_app` (the bell), " <>
          "`push` (browser and app push; off while `in_app` is off), `email` (no category yet).",
      properties: channel_flags()
    }
  end

  # The channels of `NotificationCategories` (ADR-199).
  defp channel_flags,
    do: %{
      in_app: %Schema{type: :boolean},
      push: %Schema{type: :boolean},
      email: %Schema{type: :boolean}
    }

  def preference do
    %Schema{
      title: "NotificationPreference",
      type: :object,
      required: [:audience, :category, :channels, :locked],
      properties: %{
        category: category(),
        locked: %Schema{
          type: :boolean,
          description: "Always delivered (account, security, payments); cannot be changed."
        },
        audience: %Schema{
          type: :string,
          enum: ["everyone", "staff"],
          description: "`staff`: only box staff get these, so only they need the switch."
        },
        channels: channels()
      }
    }
  end

  def preference_list do
    %Schema{
      title: "NotificationPreferenceList",
      type: :object,
      required: [:preferences],
      properties: %{preferences: %Schema{type: :array, items: preference()}}
    }
  end

  def update_request do
    %Schema{
      title: "NotificationPreferenceUpdate",
      type: :object,
      description: "One or more channels of the category to switch on or off.",
      properties: channel_flags()
    }
  end
end
