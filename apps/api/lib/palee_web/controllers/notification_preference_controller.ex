defmodule PaleeWeb.NotificationPreferenceController do
  @moduledoc "A person's per-category notification choices (ADR-199)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{MediaType, Parameter, RequestBody}
  alias Palee.Notifications
  alias PaleeWeb.Schemas.NotificationPreferences, as: Schemas

  action_fallback PaleeWeb.FallbackController

  tags(["Notifications"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "Your notification choices, per category and channel",
    responses: [ok: {"Notification preferences", "application/json", Schemas.preference_list()}]
  )

  def index(conn, _params) do
    with {:ok, preferences} <- Notifications.list_preferences(conn.assigns.user_context),
         do: json(conn, %{preferences: preferences})
  end

  operation(:update,
    summary: "Switch channels of one notification category on or off",
    parameters: [
      %Parameter{name: :category, in: :path, required: true, schema: Schemas.category()}
    ],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: Schemas.update_request()}}
    },
    responses: [ok: {"Notification preferences", "application/json", Schemas.preference_list()}]
  )

  def update(conn, %{"category" => category}) do
    with {:ok, preferences} <-
           Notifications.update_preference(
             conn.assigns.user_context,
             category,
             conn.body_params
           ),
         do: json(conn, %{preferences: preferences})
  end
end
