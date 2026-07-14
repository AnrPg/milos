defmodule MilosTrainingWeb.GamificationPreferencesController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{GetGamificationPreferences, UpdateGamificationPreferences}
  alias OpenApiSpex.Schema

  action_fallback(MilosTrainingWeb.FallbackController)

  tags(["Gamification"])
  security([%{"bearerAuth" => []}])

  operation(:show,
    summary: "Get my gamification preferences",
    responses: [ok: {"Preferences", "application/json", %Schema{type: :object}}]
  )

  def show(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)
    prefs = GetGamificationPreferences.call(current_user.id)
    json(conn, %{preferences: prefs || %{off_days: []}})
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
             maxItems: 3,
             description: "Day-of-week indices (0=Sun..6=Sat) treated as rest days"
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

    with {:ok, prefs} <- UpdateGamificationPreferences.call(current_user.id, params) do
      json(conn, %{preferences: prefs})
    end
  end
end
