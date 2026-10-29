defmodule PaleeWeb.AdminImportController do
  @moduledoc """
  Staff › Settings › Import (ADR-254): upload a CSV of another system,
  map its columns, see the dry run, apply it in the background, read the
  report, invite the people it brought in and undo it within 7 days.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Imports.PeopleImports
  alias PaleeWeb.Schemas.Imports, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Imports"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  operation(:catalog,
    summary: "Fields, presets (best guesses), date orders, limits and codes of imports",
    responses: [ok: {"Catalog", "application/json", S.catalog()}]
  )

  def catalog(conn, _params), do: json(conn, PeopleImports.catalog())

  operation(:index,
    summary: "The business's imports, newest first",
    responses: [ok: {"Imports", "application/json", S.list()}]
  )

  def index(conn, _params),
    do: json(conn, %{imports: PeopleImports.list(conn.assigns.tenant_context)})

  operation(:create,
    summary: "Upload a CSV file (≤ 5 MB, ≤ 20,000 rows) as a draft import",
    description:
      "The encoding (UTF-8/16, Windows-1252, ISO-8859-7, Windows-1253) and the delimiter " <>
        "(`,` `;` tab) are detected; the columns get a proposed mapping from the chosen " <>
        "system's preset, or the best matching one.",
    request_body: S.upload_body(),
    responses: [created: {"Import", "application/json", S.one(S.import())}]
  )

  def create(conn, _params) do
    body = conn.body_params

    with {:ok, import} <-
           PeopleImports.upload(conn.assigns.tenant_context, field(body, :file), field(body, :source)) do
      conn |> put_status(:created) |> json(%{import: import})
    end
  end

  operation(:show,
    summary: "One import with its dry run, counts per row status and outcome, and report",
    parameters: [@id],
    responses: [ok: {"Import", "application/json", S.one(S.import())}]
  )

  def show(conn, %{id: id}) do
    with {:ok, import} <- PeopleImports.show(conn.assigns.tenant_context, id),
         do: json(conn, %{import: import})
  end

  operation(:rows,
    summary: "An import's rows with their outcome, warnings and what applying them did",
    parameters: [
      @id,
      %Parameter{name: :status, in: :query, required: false, schema: S.row_status_enum()},
      %Parameter{name: :outcome, in: :query, required: false, schema: S.outcome_enum()},
      %Parameter{
        name: :after_row,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 0}
      },
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 500}
      }
    ],
    responses: [ok: {"Rows", "application/json", S.rows()}]
  )

  def rows(conn, %{id: id} = params) do
    with {:ok, page} <- PeopleImports.rows(conn.assigns.tenant_context, id, params),
         do: json(conn, page)
  end

  operation(:preview,
    summary: "Save the mapping and options of a draft and run the dry run",
    description: "Nothing is written outside the import: every row gets its outcome and warnings.",
    parameters: [@id],
    request_body: S.json_body(S.preview_body()),
    responses: [ok: {"Import", "application/json", S.one(S.import())}]
  )

  def preview(conn, %{id: id}) do
    with {:ok, import} <-
           PeopleImports.preview(conn.assigns.tenant_context, id, conn.body_params || %{}),
         do: json(conn, %{import: import})
  end

  operation(:apply,
    summary: "Apply the import in the background (each row once; again only finishes the rest)",
    parameters: [@id],
    responses: [accepted: {"Import", "application/json", S.one(S.import())}]
  )

  def apply(conn, %{id: id}) do
    with {:ok, import} <- PeopleImports.apply(conn.assigns.tenant_context, id) do
      conn |> put_status(:accepted) |> json(%{import: import})
    end
  end

  operation(:invitations,
    summary: "Email invitations to the people the import brought in (at most 200 per call)",
    description:
      "Only people with an address who have not claimed their profile and were not invited " <>
        "yet; within the business's daily invitation limits.",
    parameters: [@id],
    request_body: S.json_body(S.invitations_body()),
    responses: [ok: {"Invitations", "application/json", S.invitations()}]
  )

  def invitations(conn, %{id: id}) do
    with {:ok, result} <-
           PeopleImports.invite(conn.assigns.tenant_context, id, conn.body_params || %{}),
         do: json(conn, result)
  end

  operation(:undo,
    summary: "Undo an applied import (within 7 days of its end)",
    parameters: [@id],
    responses: [ok: {"Import", "application/json", S.one(S.import())}]
  )

  def undo(conn, %{id: id}) do
    with {:ok, import} <- PeopleImports.undo(conn.assigns.tenant_context, id),
         do: json(conn, %{import: import})
  end

  operation(:delete,
    summary: "Delete an import that was never applied",
    parameters: [@id],
    responses: [no_content: "Deleted"]
  )

  def delete(conn, %{id: id}) do
    with :ok <- PeopleImports.delete(conn.assigns.tenant_context, id),
         do: send_resp(conn, :no_content, "")
  end

  defp field(%{} = body, key), do: Map.get(body, key, Map.get(body, Atom.to_string(key)))
  defp field(_body, _key), do: nil
end
