defmodule MilosTrainingWeb.JournalController do
  @moduledoc """
  Ημερολόγιο (ADR-139): the member's feed across every entry kind, moving an
  entry on the visibility ladder (with Ζητάω απάντηση), Σημείωση notes, and a
  coach's read of one client's journal.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    GetClientJournal,
    GetJournalFeed,
    JournalAudience,
    JournalExports,
    JournalNotes,
    SetJournalVisibility
  }

  alias MilosTrainingWeb.Schemas.CrossProvider
  alias MilosTrainingWeb.Schemas.JournalFeed, as: Schemas
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Journal"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @page_params [
    %Parameter{
      name: :cursor,
      in: :query,
      required: false,
      description: "`next_cursor` of the previous page",
      schema: %Schema{type: :string}
    },
    %Parameter{
      name: :kinds,
      in: :query,
      required: false,
      description: "Comma-separated kinds to list (all when absent)",
      schema: %Schema{type: :string}
    },
    %Parameter{
      name: :limit,
      in: :query,
      required: false,
      schema: %Schema{type: :integer, minimum: 1, maximum: 100}
    }
  ]

  # ADR-162: the Ροή filter (JournalFilter); `kinds` above is its Τύπος.
  @filter_params [
    %Parameter{
      name: :sources,
      in: :query,
      required: false,
      description: "Comma-separated provider ids, `freeform`, `device`",
      schema: %Schema{type: :string}
    },
    %Parameter{
      name: :visibilities,
      in: :query,
      required: false,
      description: "Comma-separated rungs",
      schema: %Schema{type: :string}
    },
    %Parameter{
      name: :date_from,
      in: :query,
      required: false,
      schema: %Schema{type: :string, format: :date}
    },
    %Parameter{
      name: :date_to,
      in: :query,
      required: false,
      schema: %Schema{type: :string, format: :date}
    },
    %Parameter{
      name: :q,
      in: :query,
      required: false,
      description: "Text search (2–100 characters) over entries and their comments",
      schema: %Schema{type: :string}
    },
    %Parameter{
      name: :remember,
      in: :query,
      required: false,
      description: "Also remember this filter as your last-used Ημερολόγιο filter",
      schema: %Schema{type: :boolean}
    }
  ]

  @id_param %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:index,
    summary: "Your journal across every provider: every entry kind, newest first",
    parameters: @page_params ++ @filter_params,
    responses: [ok: {"Feed page", "application/json", Schemas.page()}]
  )

  def index(conn, params) do
    with {:ok, page} <- GetJournalFeed.call(conn.assigns.user_context, feed_params(params)) do
      json(conn, page)
    end
  end

  operation(:coach_audience,
    summary: "Who «Οι coach μου» means across your providers",
    responses: [ok: {"Audience", "application/json", CrossProvider.coach_audience_response()}]
  )

  def coach_audience(conn, _params) do
    with {:ok, audience} <- JournalAudience.get_default(conn.assigns.user_context) do
      json(conn, audience)
    end
  end

  operation(:put_coach_audience,
    summary: "Choose which providers' coaches «Οι coach μου» means",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{schema: CrossProvider.coach_audience_request()}
      }
    },
    responses: [
      ok: {"Audience", "application/json", CrossProvider.coach_audience_response()},
      unprocessable_entity: {"Unknown provider", "application/json", %Schema{type: :object}}
    ]
  )

  def put_coach_audience(conn, _params) do
    with {:ok, audience} <-
           JournalAudience.put_default(
             conn.assigns.user_context,
             body_params(conn)["organization_ids"]
           ) do
      json(conn, audience)
    end
  end

  operation(:entry_audience,
    summary: "Share one entry with specific providers (or reset it)",
    parameters: [
      %Parameter{
        name: :kind,
        in: :path,
        required: true,
        schema: %Schema{type: :string, enum: ~w(execution training_log pr note check_in)}
      },
      @id_param
    ],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{schema: CrossProvider.entry_audience_request()}
      }
    },
    responses: [
      ok: {"Audience", "application/json", CrossProvider.entry_audience_response()},
      not_found: {"Entry not found", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Not allowed", "application/json", %Schema{type: :object}}
    ]
  )

  def entry_audience(conn, %{kind: kind, id: id}) do
    with {:ok, result} <-
           JournalAudience.put_entry(
             conn.assigns.user_context,
             kind,
             id,
             body_params(conn)["organization_ids"]
           ) do
      json(conn, result)
    end
  end

  operation(:export,
    summary: "Export your whole journal across providers (JSON and training CSV)",
    responses: [
      accepted: {"Export requested", "application/json", CrossProvider.export_response()},
      conflict: {"An export is pending", "application/json", %Schema{type: :object}}
    ]
  )

  def export(conn, _params) do
    with {:ok, export} <- JournalExports.request(conn.assigns.user_context) do
      conn
      |> put_status(:accepted)
      |> json(%{export: export})
    end
  end

  operation(:exports,
    summary: "Your journal exports, with short-lived download links",
    responses: [ok: {"Exports", "application/json", CrossProvider.exports_response()}]
  )

  def exports(conn, _params) do
    with {:ok, exports} <- JournalExports.list(conn.assigns.user_context) do
      json(conn, %{exports: exports})
    end
  end

  operation(:set_visibility,
    summary: "Move one of your entries on the visibility ladder",
    parameters: [
      %Parameter{
        name: :kind,
        in: :path,
        required: true,
        schema: %Schema{type: :string, enum: Schemas.movable_kinds()}
      },
      @id_param
    ],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: Schemas.visibility_request()}}
    },
    responses: [
      ok: {"New rung", "application/json", Schemas.visibility_response()},
      not_found: {"Entry not found", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Rung not allowed", "application/json", %Schema{type: :object}}
    ]
  )

  def set_visibility(conn, %{kind: kind, id: id}) do
    with {:ok, result} <-
           SetJournalVisibility.call(conn.assigns.user_context, kind, id, body_params(conn)) do
      json(conn, result)
    end
  end

  operation(:create_note,
    summary: "Write a Σημείωση",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: Schemas.note_create_request()}}
    },
    responses: [created: {"Note", "application/json", Schemas.note_response()}]
  )

  def create_note(conn, _params) do
    with {:ok, note} <- JournalNotes.create(conn.assigns.user_context, body_params(conn)) do
      conn
      |> put_status(:created)
      |> json(%{note: note})
    end
  end

  operation(:update_note,
    summary: "Edit one of your notes",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: Schemas.note_update_request()}}
    },
    responses: [ok: {"Note", "application/json", Schemas.note_response()}]
  )

  def update_note(conn, %{id: id}) do
    with {:ok, note} <- JournalNotes.update(conn.assigns.user_context, id, body_params(conn)) do
      json(conn, %{note: note})
    end
  end

  operation(:delete_note,
    summary: "Delete one of your notes",
    parameters: [@id_param],
    responses: [no_content: "Deleted"]
  )

  def delete_note(conn, %{id: id}) do
    with :ok <- JournalNotes.delete(conn.assigns.user_context, id) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:client_journal,
    summary: "A client's journal as their coach may read it (audited)",
    parameters: [
      %Parameter{
        name: :user_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
      | @page_params
    ],
    responses: [ok: {"Feed page", "application/json", Schemas.page()}]
  )

  def client_journal(conn, %{user_id: user_id} = params) do
    with {:ok, page} <-
           GetClientJournal.call(conn.assigns.tenant_context, user_id, page_params(params)) do
      json(conn, page)
    end
  end

  defp page_params(params), do: Map.take(params, [:cursor, :kinds, :limit])

  defp feed_params(params),
    do:
      Map.take(params, [
        :cursor,
        :kinds,
        :limit,
        :sources,
        :visibilities,
        :date_from,
        :date_to,
        :q,
        :remember
      ])

  # CastAndValidate atomizes body keys; the application reads string keys.
  defp body_params(conn), do: conn.body_params |> Jason.encode!() |> Jason.decode!()
end
