defmodule PaleeWeb.MyBodyController do
  @moduledoc """
  Ημερολόγιο › Σώμα (ADR-158): your measurement snapshots, private photos,
  series and comparisons, body settings, health consents and who of your
  coaches looked at what you shared.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{BodyPhotos, BodyShare, BodySnapshots, MyBody}
  alias PaleeWeb.Schemas.Body, as: S
  alias PaleeWeb.Schemas.Media
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Body"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}
  @photo_id %Parameter{name: :photo_id, in: :path, required: true, schema: S.uuid()}
  @scope %Parameter{
    name: :scope,
    in: :path,
    required: true,
    schema: %Schema{type: :string, enum: Palee.Body.consent_scopes()}
  }
  @snapshot {"Snapshot", "application/json", S.snapshot_response()}
  @no_content {"Done", "application/json", %Schema{type: :object}}

  operation(:index,
    summary: "Your body snapshots, newest first",
    parameters: [
      %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100}
      }
    ],
    responses: [ok: {"Snapshots", "application/json", S.snapshot_page()}]
  )

  def index(conn, params) do
    with {:ok, page} <- BodySnapshots.list(conn.assigns.user_context, params),
         do: json(conn, page)
  end

  operation(:show,
    summary: "One of your snapshots",
    parameters: [@id],
    responses: [ok: @snapshot]
  )

  def show(conn, %{id: id}) do
    with {:ok, snapshot} <- BodySnapshots.get(conn.assigns.user_context, id),
         do: json(conn, %{snapshot: snapshot})
  end

  operation(:create,
    summary: "Save a snapshot: metrics in your units and/or photos (private by default)",
    request_body: S.body(S.create_request()),
    responses: [created: @snapshot]
  )

  def create(conn, _params) do
    with {:ok, snapshot} <- BodySnapshots.create(conn.assigns.user_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{snapshot: snapshot})
    end
  end

  operation(:update,
    summary: "Edit a snapshot (metrics merge; null removes one)",
    parameters: [@id],
    request_body: S.body(S.update_request()),
    responses: [ok: @snapshot]
  )

  def update(conn, %{id: id}) do
    with {:ok, snapshot} <- BodySnapshots.update(conn.assigns.user_context, id, conn.body_params),
         do: json(conn, %{snapshot: snapshot})
  end

  operation(:delete,
    summary: "Delete a snapshot and its photos",
    parameters: [@id],
    responses: [no_content: @no_content]
  )

  def delete(conn, %{id: id}) do
    with :ok <- BodySnapshots.delete(conn.assigns.user_context, id),
         do: send_resp(conn, :no_content, "")
  end

  operation(:series,
    summary: "One metric over time, smoothed, with a trend word (as your display allows)",
    parameters: [
      %Parameter{
        name: :metric,
        in: :query,
        required: true,
        schema: %Schema{type: :string, enum: Palee.Body.metric_keys()}
      },
      %Parameter{
        name: :range,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: Palee.Body.ranges()}
      }
    ],
    responses: [ok: {"Series", "application/json", S.series()}]
  )

  def series(conn, params) do
    with {:ok, series} <- BodySnapshots.series(conn.assigns.user_context, params),
         do: json(conn, series)
  end

  operation(:compare,
    summary: "Two snapshots side by side, with the change of each metric",
    parameters: [
      %Parameter{name: :from, in: :query, required: true, schema: S.uuid()},
      %Parameter{name: :to, in: :query, required: true, schema: S.uuid()}
    ],
    responses: [ok: {"Comparison", "application/json", S.compare()}]
  )

  def compare(conn, params) do
    with {:ok, comparison} <- BodySnapshots.compare(conn.assigns.user_context, params),
         do: json(conn, comparison)
  end

  operation(:upload,
    summary: "Reserve an upload for a body photo (needs your body-photo consent)",
    request_body: S.body(S.upload_request()),
    responses: [ok: {"Upload", "application/json", Media.upload()}]
  )

  def upload(conn, _params) do
    with {:ok, upload} <- BodyPhotos.request_upload(conn.assigns.user_context, conn.body_params),
         do: json(conn, upload)
  end

  operation(:add_photo,
    summary: "Add an uploaded photo to a snapshot",
    parameters: [@id],
    request_body: S.body(S.photo_request()),
    responses: [created: {"Photo", "application/json", S.photo_response()}]
  )

  def add_photo(conn, %{id: id}) do
    with {:ok, photo} <- BodyPhotos.add(conn.assigns.user_context, id, conn.body_params) do
      conn |> put_status(:created) |> json(%{photo: photo})
    end
  end

  operation(:remove_photo,
    summary: "Remove a photo from a snapshot (the file is deleted)",
    parameters: [@id, @photo_id],
    responses: [no_content: @no_content]
  )

  def remove_photo(conn, %{id: id, photo_id: photo_id}) do
    with :ok <- BodyPhotos.remove(conn.assigns.user_context, id, photo_id),
         do: send_resp(conn, :no_content, "")
  end

  operation(:latest_photos,
    summary: "Your latest photo of each pose, for the camera's outline",
    responses: [ok: {"Photos", "application/json", S.photos_response()}]
  )

  def latest_photos(conn, _params),
    do: json(conn, %{photos: BodyPhotos.latest(conn.assigns.user_context)})

  operation(:delete_photos,
    summary: "Delete all your body photos (files included)",
    responses: [ok: {"Deleted", "application/json", S.delete_all_response()}]
  )

  def delete_photos(conn, _params) do
    with {:ok, result} <- BodyPhotos.delete_all(conn.assigns.user_context), do: json(conn, result)
  end

  operation(:share,
    summary: "Share a before/after of one pose as a post (explicit confirmation; photos copied)",
    request_body: S.body(S.share_request()),
    responses: [
      created: {"Post", "application/json", PaleeWeb.Schemas.Community.post_response()}
    ]
  )

  def share(conn, _params) do
    with {:ok, post} <- BodyShare.call(conn.assigns.user_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{post: post})
    end
  end

  operation(:settings,
    summary: "Your body settings and the metric catalog in your units",
    responses: [ok: {"Settings", "application/json", S.settings_response()}]
  )

  def settings(conn, _params) do
    with {:ok, settings} <- MyBody.settings(conn.assigns.user_context), do: json(conn, settings)
  end

  operation(:update_settings,
    summary: "Change your body settings (units, weight display, sections, reminder)",
    request_body: S.body(S.settings_request()),
    responses: [ok: {"Settings", "application/json", S.settings_response()}]
  )

  def update_settings(conn, _params) do
    with {:ok, settings} <- MyBody.update_settings(conn.assigns.user_context, conn.body_params),
         do: json(conn, settings)
  end

  operation(:consents,
    summary: "Your health consents",
    responses: [ok: {"Consents", "application/json", S.consents_response()}]
  )

  def consents(conn, _params) do
    with {:ok, consents} <- MyBody.consents(conn.assigns.user_context),
         do: json(conn, %{consents: consents})
  end

  operation(:grant_consent,
    summary: "Give a health consent",
    parameters: [@scope],
    responses: [ok: {"Consents", "application/json", S.consents_response()}]
  )

  def grant_consent(conn, %{scope: scope}) do
    with {:ok, consents} <- MyBody.grant(conn.assigns.user_context, scope),
         do: json(conn, %{consents: consents})
  end

  operation(:withdraw_consent,
    summary: "Withdraw a health consent (coaches stop seeing your photos at once)",
    parameters: [@scope],
    responses: [ok: {"Consents", "application/json", S.consents_response()}]
  )

  def withdraw_consent(conn, %{scope: scope}) do
    with {:ok, consents} <- MyBody.withdraw(conn.assigns.user_context, scope),
         do: json(conn, %{consents: consents})
  end

  operation(:access_log,
    summary: "Which coaches looked at the snapshots you shared, and when",
    responses: [ok: {"Access log", "application/json", S.access_log_response()}]
  )

  def access_log(conn, _params) do
    with {:ok, entries} <- MyBody.access_log(conn.assigns.user_context),
         do: json(conn, %{entries: entries})
  end
end
