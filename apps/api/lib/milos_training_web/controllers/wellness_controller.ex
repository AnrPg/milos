defmodule MilosTrainingWeb.WellnessController do
  @moduledoc "Ημερολόγιο › Ευεξία of the current user: water, sleep, meals, Λιγούρα (ADR-159)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    ChangeCraving,
    ChangeWellnessEntry,
    EraseMyWellness,
    ExportMyWellness,
    GetMyWellness,
    LogCraving,
    LogWellnessEntry,
    MealPhotos,
    SetWellnessPreferences
  }

  alias MilosTraining.Wellness
  alias MilosTrainingWeb.Schemas.Wellness, as: Schemas
  alias MilosTrainingWeb.WellnessJSON
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Wellness"])
  security([%{"bearerAuth" => []}])

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:show,
    summary: "The member's wellness days (Σήμερα card, week strip) from..to, local dates",
    parameters: [
      %Parameter{
        name: :from,
        in: :query,
        required: true,
        schema: %Schema{type: :string, format: :date}
      },
      %Parameter{
        name: :to,
        in: :query,
        required: true,
        schema: %Schema{type: :string, format: :date}
      }
    ],
    responses: [ok: {"Days, entries and targets", "application/json", Schemas.overview()}]
  )

  def show(conn, params) do
    with {:ok, payload} <- GetMyWellness.call(conn.assigns.user_context, params) do
      json(conn, WellnessJSON.overview(payload))
    end
  end

  operation(:upload_meal_photo,
    summary: "Reserve an upload for a meal photo (needs your health-data consent)",
    request_body: Schemas.body(MilosTrainingWeb.Schemas.Media.upload_request()),
    responses: [ok: {"Upload", "application/json", MilosTrainingWeb.Schemas.Media.upload()}]
  )

  def upload_meal_photo(conn, _params) do
    with {:ok, upload} <- MealPhotos.request_upload(conn.assigns.user_context, conn.body_params),
         do: json(conn, upload)
  end

  operation(:create_entry,
    summary: "Log water, sleep or a meal",
    request_body: Schemas.body(Schemas.entry_request()),
    responses: [created: {"Entry", "application/json", Schemas.entry_response()}]
  )

  def create_entry(conn, params) do
    with {:ok, entry} <-
           LogWellnessEntry.call(conn.assigns.user_context, body_params(conn, params)) do
      conn |> put_status(:created) |> json(%{entry: WellnessJSON.entry(entry)})
    end
  end

  operation(:update_entry,
    summary: "Correct one of your wellness entries",
    parameters: [@id],
    request_body: Schemas.body(Schemas.entry_change_request()),
    responses: [ok: {"Entry", "application/json", Schemas.entry_response()}]
  )

  def update_entry(conn, %{"id" => id} = params) do
    with {:ok, entry} <-
           ChangeWellnessEntry.update(conn.assigns.user_context, id, body_params(conn, params)) do
      json(conn, %{entry: WellnessJSON.entry(entry)})
    end
  end

  operation(:delete_entry,
    summary: "Remove one of your wellness entries (undo a glass, a meal, a night)",
    parameters: [@id],
    responses: [no_content: "Deleted"]
  )

  def delete_entry(conn, %{"id" => id}) do
    with {:ok, _entry} <- ChangeWellnessEntry.delete(conn.assigns.user_context, id) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:create_craving,
    summary: "Log a Λιγούρα",
    request_body: Schemas.body(Schemas.craving_request()),
    responses: [created: {"Craving", "application/json", Schemas.craving_response()}]
  )

  def create_craving(conn, params) do
    with {:ok, craving} <- LogCraving.call(conn.assigns.user_context, body_params(conn, params)) do
      conn |> put_status(:created) |> json(%{craving: WellnessJSON.craving(craving)})
    end
  end

  operation(:update_craving,
    summary: "Update a Λιγούρα (e.g. how it went)",
    parameters: [@id],
    request_body: Schemas.body(Schemas.craving_request()),
    responses: [ok: {"Craving", "application/json", Schemas.craving_response()}]
  )

  def update_craving(conn, %{"id" => id} = params) do
    with {:ok, craving} <-
           ChangeCraving.update(conn.assigns.user_context, id, body_params(conn, params)) do
      json(conn, %{craving: WellnessJSON.craving(craving)})
    end
  end

  operation(:delete_craving,
    summary: "Remove one of your Λιγούρες",
    parameters: [@id],
    responses: [no_content: "Deleted"]
  )

  def delete_craving(conn, %{"id" => id}) do
    with {:ok, _craving} <- ChangeCraving.delete(conn.assigns.user_context, id) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:preferences,
    summary: "Your wellness targets and hidden items",
    responses: [ok: {"Preferences", "application/json", Schemas.preferences_response()}]
  )

  def preferences(conn, _params) do
    %{user_id: user_id} = context = conn.assigns.user_context
    prefs = Wellness.with_context(context, fn -> Wellness.preferences(user_id) end)
    json(conn, %{preferences: WellnessJSON.preferences(prefs)})
  end

  operation(:update_preferences,
    summary: "Set your water goal, glass size, sleep goal or hidden items",
    request_body: Schemas.body(Schemas.preferences_request()),
    responses: [ok: {"Preferences", "application/json", Schemas.preferences_response()}]
  )

  def update_preferences(conn, params) do
    with {:ok, prefs} <-
           SetWellnessPreferences.call(conn.assigns.user_context, body_params(conn, params)) do
      json(conn, %{preferences: WellnessJSON.preferences(prefs)})
    end
  end

  operation(:erase,
    summary: "Delete every entry of a section (wellness, cravings); irreversible",
    parameters: [
      %Parameter{
        name: :sections,
        in: :query,
        required: true,
        schema: %Schema{type: :string, example: "wellness,cravings"}
      }
    ],
    responses: [ok: {"Rows erased per section", "application/json", Schemas.erase_response()}]
  )

  def erase(conn, params) do
    with {:ok, counts} <- EraseMyWellness.call(conn.assigns.user_context, params) do
      json(conn, %{erased: counts})
    end
  end

  operation(:export,
    summary: "Your wellness and/or cravings as JSON, meal photos as signed links",
    parameters: [
      %Parameter{
        name: :sections,
        in: :query,
        required: true,
        schema: %Schema{type: :string, example: "wellness,cravings"}
      }
    ],
    responses: [ok: {"Export", "application/json", Schemas.export_response()}]
  )

  def export(conn, params) do
    with {:ok, export} <- ExportMyWellness.call(conn.assigns.user_context, params) do
      conn
      |> put_resp_header("content-disposition", ~s(attachment; filename="milos-wellness.json"))
      |> json(export)
    end
  end

  defp body_params(conn, params), do: Map.merge(Map.drop(params, ["id"]), conn.body_params)
end
