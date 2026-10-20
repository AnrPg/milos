defmodule MilosTrainingWeb.TrialController do
  @moduledoc "A visitor's trials: asking at a box, their own trials, the follow-up (ADR-144)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.Trials
  alias MilosTrainingWeb.Schemas.Trials, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Trials"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @slug %Parameter{
    name: :slug,
    in: :path,
    required: true,
    description: "The box's slug or one of its former slugs",
    schema: %Schema{type: :string, maxLength: 120}
  }
  @refused [
    not_found: {"No such box, class or trial", "application/json", %Schema{type: :object}},
    unprocessable_entity:
      {"The box can't take this trial", "application/json", %Schema{type: :object}}
  ]

  operation(:create,
    summary: "Ask for (or book) a trial in a class of a published box",
    parameters: [@slug],
    request_body: S.body(S.request()),
    responses: [created: {"Trial", "application/json", S.mine_response()}] ++ @refused
  )

  def create(conn, %{slug: slug}) do
    with {:ok, trial} <- Trials.request(account(conn), slug, conn.body_params) do
      conn |> put_status(:created) |> json(%{trial: trial})
    end
  end

  operation(:index,
    summary: "Your trials at every box: upcoming, and recent ones with something to show",
    responses: [ok: {"Trials", "application/json", S.mine_list()}]
  )

  def index(conn, _params), do: json(conn, %{trials: Trials.mine(account(conn))})

  operation(:show,
    summary: "One of your trials",
    parameters: [@id],
    responses: [ok: {"Trial", "application/json", S.mine_response()}] ++ @refused
  )

  def show(conn, %{id: id}) do
    with {:ok, trial} <- Trials.get_mine(account(conn), id), do: json(conn, %{trial: trial})
  end

  operation(:cancel,
    summary: "Cancel your trial (frees the seat, or withdraws the ask)",
    parameters: [@id],
    responses: [ok: {"Trial", "application/json", S.mine_response()}] ++ @refused
  )

  def cancel(conn, %{id: id}) do
    with {:ok, trial} <- Trials.cancel(account(conn), id), do: json(conn, %{trial: trial})
  end

  operation(:follow_up,
    summary:
      "After the trial: «Θέλω να γραφτώ» opens a chat with the box, «Όχι τώρα» hides the card",
    parameters: [@id],
    request_body: S.body(S.follow_up_request()),
    responses: [ok: {"Trial", "application/json", S.follow_up_response()}] ++ @refused
  )

  def follow_up(conn, %{id: id}) do
    action = String.to_existing_atom(conn.body_params.action)

    with {:ok, result} <- Trials.follow_up(account(conn), id, action), do: json(conn, result)
  end

  defp account(conn), do: conn.assigns.user_context.account
end
