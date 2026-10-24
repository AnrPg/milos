defmodule PaleeWeb.PartnersController do
  @moduledoc """
  Partners (ADR-169): a member's profile, the deck and swipes in one club;
  their matches across clubs, each match's conversation and «Κλείστε μαζί»;
  the Ρυθμίσεις switch; blocking a person.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{PartnerMatches, Partners, PeopleBlocks}
  alias PaleeWeb.Schemas.Partners, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Partners"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}
  @club_id %Parameter{name: :club_id, in: :path, required: true, schema: S.uuid()}

  defp ctx(conn), do: conn.assigns.user_context

  # ------------------------------------------------------------- one club

  operation(:club,
    summary: "Partners in a club as it applies to you: offered?, your profile, the options",
    parameters: [@club_id],
    responses: [ok: {"Overview", "application/json", S.overview()}]
  )

  def club(conn, %{club_id: club_id}) do
    with {:ok, overview} <- Partners.overview(ctx(conn), club_id), do: json(conn, overview)
  end

  operation(:put_profile,
    summary: "Opt in or change your Partners profile in a club (a member of the club only)",
    parameters: [@club_id],
    request_body: S.body(S.profile_request()),
    responses: [ok: {"Profile", "application/json", S.profile_response()}]
  )

  def put_profile(conn, %{club_id: club_id}) do
    with {:ok, profile} <- Partners.put_profile(ctx(conn), club_id, conn.body_params),
         do: json(conn, %{profile: profile})
  end

  operation(:deck,
    summary: "The next people of the club who opted in, best fit first",
    parameters: [
      @club_id,
      %Parameter{
        name: :time,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: Palee.Partners.times()}
      },
      %Parameter{
        name: :level,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: Palee.Partners.levels()}
      },
      %Parameter{
        name: :goal,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: Palee.Partners.goals()}
      },
      %Parameter{
        name: :discipline,
        in: :query,
        required: false,
        description: "People who named this discipline (ADR-197)",
        schema: %Schema{type: :string, enum: Palee.Organizations.box_disciplines()}
      },
      %Parameter{
        name: :within_km,
        in: :query,
        required: false,
        description:
          "Open clubs only (ADR-197): people who show in Γύρω μου with a main neighbourhood this close to yours",
        schema: %Schema{type: :integer, enum: Palee.Partners.distances_km()}
      }
    ],
    responses: [ok: {"Deck", "application/json", S.deck()}]
  )

  def deck(conn, %{club_id: club_id} = params) do
    filters =
      params
      |> Map.take([:time, :level, :goal, :discipline, :within_km])
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    with {:ok, deck} <- Partners.deck(ctx(conn), club_id, filters), do: json(conn, deck)
  end

  operation(:swipe,
    summary: "Like or pass; a like answered by a like makes a match",
    parameters: [@club_id],
    request_body: S.body(S.swipe_request()),
    responses: [ok: {"Swipe", "application/json", S.swipe_response()}]
  )

  def swipe(conn, %{club_id: club_id}) do
    with {:ok, result} <- Partners.swipe(ctx(conn), club_id, conn.body_params),
         do: json(conn, result)
  end

  operation(:undo,
    summary: "Take back a swipe that made no match",
    parameters: [
      @club_id,
      %Parameter{name: :target_id, in: :path, required: true, schema: S.uuid()}
    ],
    responses: [ok: {"Undone", "application/json", S.undo_response()}]
  )

  def undo(conn, %{club_id: club_id, target_id: target_id}) do
    with {:ok, result} <- Partners.undo(ctx(conn), club_id, target_id), do: json(conn, result)
  end

  # ------------------------------------------------------------- matches

  operation(:matches,
    summary: "Your Partners matches, latest conversation first",
    responses: [ok: {"Matches", "application/json", S.matches_response()}]
  )

  def matches(conn, _params) do
    with {:ok, matches} <- PartnerMatches.list(ctx(conn)), do: json(conn, matches)
  end

  operation(:end_match,
    summary: "End a match quietly; its conversation stays readable",
    parameters: [@id],
    responses: [ok: {"Ended", "application/json", S.match_ended()}]
  )

  def end_match(conn, %{id: id}) do
    with {:ok, result} <- PartnerMatches.end_match(ctx(conn), id), do: json(conn, result)
  end

  operation(:messages,
    summary: "A page of the match's conversation, newest first",
    parameters: [
      @id,
      %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100}
      }
    ],
    responses: [ok: {"Messages", "application/json", S.message_page()}]
  )

  def messages(conn, %{id: id} = params) do
    page_params = %{"cursor" => Map.get(params, :cursor), "limit" => Map.get(params, :limit)}
    with {:ok, page} <- PartnerMatches.messages(ctx(conn), id, page_params), do: json(conn, page)
  end

  operation(:post_message,
    summary: "Write in an active match's conversation",
    parameters: [@id],
    request_body: S.body(S.message_request()),
    responses: [created: {"Message", "application/json", S.message_response()}]
  )

  def post_message(conn, %{id: id}) do
    with {:ok, message} <- PartnerMatches.post(ctx(conn), id, conn.body_params) do
      conn |> put_status(:created) |> json(%{message: message})
    end
  end

  operation(:mark_read,
    summary: "Mark the conversation read",
    parameters: [@id],
    responses: [ok: {"Read", "application/json", S.read_response()}]
  )

  def mark_read(conn, %{id: id}) do
    with {:ok, result} <- PartnerMatches.mark_read(ctx(conn), id), do: json(conn, result)
  end

  operation(:sessions,
    summary: "«Κλείστε μαζί»: the gym's next classes that suit you both",
    parameters: [@id],
    responses: [ok: {"Sessions", "application/json", S.sessions_response()}]
  )

  def sessions(conn, %{id: id}) do
    with {:ok, result} <- PartnerMatches.sessions(ctx(conn), id), do: json(conn, result)
  end

  operation(:plan,
    summary: "Suggest a class in the conversation («Κλείστε μαζί»)",
    parameters: [@id],
    request_body: S.body(S.plan_request()),
    responses: [created: {"Message", "application/json", S.message_response()}]
  )

  def plan(conn, %{id: id}) do
    with {:ok, message} <- PartnerMatches.plan(ctx(conn), id, conn.body_params) do
      conn |> put_status(:created) |> json(%{message: message})
    end
  end

  # ------------------------------------------------------------- settings

  operation(:settings,
    summary: "Ρυθμίσεις › Partners: whether others in your clubs see you",
    responses: [ok: {"Settings", "application/json", S.settings()}]
  )

  def settings(conn, _params) do
    with {:ok, settings} <- Partners.settings(ctx(conn)), do: json(conn, settings)
  end

  operation(:put_settings,
    summary: "Pause or resume every Partners profile at once",
    request_body: S.body(S.settings_request()),
    responses: [ok: {"Settings", "application/json", S.settings()}]
  )

  def put_settings(conn, _params) do
    with {:ok, settings} <- Partners.put_settings(ctx(conn), conn.body_params),
         do: json(conn, settings)
  end

  # ------------------------------------------------------------- blocks

  operation(:blocks,
    summary: "People you blocked",
    responses: [ok: {"Blocked people", "application/json", S.blocks_response()}]
  )

  def blocks(conn, _params) do
    with {:ok, result} <- PeopleBlocks.list(ctx(conn)), do: json(conn, result)
  end

  operation(:block,
    summary:
      "Block a person: Partners matches and buddy links between you end; they are not told",
    request_body: S.body(S.block_request()),
    responses: [ok: {"Blocked", "application/json", S.block_response()}]
  )

  def block(conn, _params) do
    with {:ok, result} <- PeopleBlocks.block(ctx(conn), conn.body_params.user_id),
         do: json(conn, result)
  end

  operation(:unblock,
    summary: "Unblock a person (ended matches and links stay ended)",
    parameters: [%Parameter{name: :user_id, in: :path, required: true, schema: S.uuid()}],
    responses: [ok: {"Unblocked", "application/json", S.block_response()}]
  )

  def unblock(conn, %{user_id: user_id}) do
    with {:ok, result} <- PeopleBlocks.unblock(ctx(conn), user_id), do: json(conn, result)
  end
end
