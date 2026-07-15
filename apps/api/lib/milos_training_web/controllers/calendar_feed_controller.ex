defmodule MilosTrainingWeb.CalendarFeedController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.{GetCalendarExportLinks, GetCalendarFeed}
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Calendar"])

  operation(:links,
    summary: "Get signed calendar export links for the current user",
    security: [%{"bearerAuth" => []}],
    responses: [
      ok:
        {"Calendar links", "application/json", %Schema{type: :object, additionalProperties: true}}
    ]
  )

  def links(conn, _params) do
    user = GuardianPlug.current_resource(conn)

    with {:ok, payload} <- GetCalendarExportLinks.call(user) do
      json(conn, payload)
    end
  end

  operation(:regenerate_links,
    summary: "Regenerate calendar export links and revoke previous feed URLs",
    security: [%{"bearerAuth" => []}],
    responses: [
      ok:
        {"Calendar links", "application/json", %Schema{type: :object, additionalProperties: true}}
    ]
  )

  def regenerate_links(conn, _params) do
    user = GuardianPlug.current_resource(conn)

    with {:ok, payload} <- GetCalendarExportLinks.call(user, regenerate: true) do
      json(conn, payload)
    end
  end

  operation(:feed,
    summary: "Fetch a signed user calendar feed",
    parameters: [
      %Parameter{name: :token, in: :query, required: true, schema: %Schema{type: :string}},
      %Parameter{name: :download, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    responses: [
      ok: {"iCalendar feed", "text/calendar", %Schema{type: :string}},
      unauthorized: {"Invalid calendar token", "application/json", %Schema{type: :object}}
    ]
  )

  def feed(conn, %{"token" => token} = params) do
    with {:ok, ics} <- GetCalendarFeed.call(token) do
      conn
      |> put_resp_content_type("text/calendar")
      |> maybe_download(params)
      |> send_resp(200, ics)
    end
  end

  def feed(_conn, _params), do: {:error, :unauthorized}

  defp maybe_download(conn, %{"download" => value}) when value in ["1", "true"] do
    put_resp_header(conn, "content-disposition", ~s(attachment; filename="milos-training.ics"))
  end

  defp maybe_download(conn, _params), do: conn
end
