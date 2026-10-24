defmodule PaleeWeb.GamificationPreferencesController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{GetGamificationPreferences, UpdateGamificationPreferences}
  alias OpenApiSpex.Schema

  action_fallback(PaleeWeb.FallbackController)

  tags(["Gamification"])
  security([%{"bearerAuth" => []}])

  operation(:show,
    summary: "Get my gamification preferences",
    responses: [ok: {"Preferences", "application/json", %Schema{type: :object}}]
  )

  def show(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, prefs} <-
           GetGamificationPreferences.call(conn.assigns.user_context, current_user.id) do
      json(conn, %{preferences: prefs || GetGamificationPreferences.defaults()})
    end
  end

  operation(:update,
    summary: "Update my gamification preferences",
    request_body:
      {"Preferences params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           off_days: %Schema{
             type: :array,
             items: %Schema{type: :integer, minimum: 0, maximum: 6},
             maxItems: 5,
             description: "Day-of-week indices (0=Sun..6=Sat) treated as rest days"
           },
           pr_celebrations: %Schema{
             type: :boolean,
             description:
               "ADR-196: an automatic card in my clubs when I set a PR (off by default)"
           },
           challenge_rankings: %Schema{
             type: :boolean,
             description: "ADR-196: appear in challenge rankings (on by default)"
           }
         }
       }},
    responses: [
      ok: {"Preferences", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def update(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, prefs} <-
           UpdateGamificationPreferences.call(conn.assigns.user_context, current_user.id, params) do
      json(conn, %{preferences: prefs})
    end
  end
end
