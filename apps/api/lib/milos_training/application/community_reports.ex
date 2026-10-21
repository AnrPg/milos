defmodule MilosTraining.Application.CommunityReports do
  @moduledoc """
  Reports (ADR-143, board 7 Q4–Q5). A member reports a post, a comment or a
  group they can see, with a reason and an optional note; it disappears for
  them and the gym's staff hear about it. Staff see one queue grouped by item
  and act once per item: hide, delete, archive the group, or nothing needed.

  ADR-157: a post's preview shows its photos and video poster (thumbnails),
  so staff judge what people reported without opening it.

  ADR-169: a person's Partners profile can be reported too (`partner`).
  Reporting someone also blocks them, so the reporter never meets them
  again; staff hide the profile (suspended in that club) or dismiss.
  """

  alias MilosTraining.Application.{
    ClubScope,
    CommunityGroups,
    CommunityPeople,
    CommunityPosts,
    MediaUrls,
    Partners,
    PeopleBlocks
  }

  alias MilosTraining.{Community, Notifications, Organizations}

  def report(context, params) do
    with {:ok, club, target} <- target(context, params[:target_type], params[:target_id]),
         true <- params[:reason] in Community.report_reasons() || {:error, :invalid_reason},
         {:ok, report} <-
           Community.report(ClubScope.write_context(club, context), target, %{
             reason: params[:reason],
             note: params[:note]
           }) do
      if report != :already_reported, do: notify_staff(club, target, params[:reason])
      if target.type == "partner", do: PeopleBlocks.block(context, target.author_id, "reported")
      {:ok, %{target_type: target.type, target_id: target.id, reported: true}}
    end
  end

  @doc "Open reports of the gym, one row per reported item."
  def queue(context) do
    with {:ok, _club} <- staff_club(context) do
      reports = Community.list_reports(context, %{status: "open"})

      rows =
        reports
        |> Enum.group_by(&{&1.target_type, &1.target_id})
        |> Enum.map(fn {{type, id}, item_reports} -> row(context, type, id, item_reports) end)
        |> Enum.sort_by(& &1.last_reported_at, {:desc, DateTime})

      people = CommunityPeople.by_ids(Enum.map(rows, & &1.author_id))
      {:ok, Enum.map(rows, &present_row(&1, people))}
    end
  end

  def act(context, target_type, target_id, action) do
    with {:ok, _club} <- staff_club(context),
         true <-
           Community.report_action_applies?(action, target_type) || {:error, :invalid_action},
         :ok <- apply_action(context, target_type, target_id, action),
         {:ok, count} <- Community.resolve_reports(context, target_type, target_id, action) do
      {:ok, %{target_type: target_type, target_id: target_id, action: action, resolved: count}}
    end
  end

  # ------------------------------------------------------------- internals

  defp target(context, "post", id) do
    with {:ok, club, channel, post} <- CommunityPosts.load(context, id),
         do:
           {:ok, club,
            %{
              type: "post",
              id: post.id,
              author_id: post.author_id,
              club_id: club.id,
              channel_id: channel.id
            }}
  end

  defp target(context, "comment", id) do
    with {:ok, club, channel, _post, comment} <- CommunityPosts.load_comment(context, id),
         do:
           {:ok, club,
            %{
              type: "comment",
              id: comment.id,
              author_id: comment.author_id,
              club_id: club.id,
              channel_id: channel.id
            }}
  end

  defp target(context, "channel", id) do
    with {:ok, clubs} <- ClubScope.reachable(context),
         %{kind: "member_group"} = group <-
           Community.get_channel(context, id) || {:error, :not_found},
         %{} = club <- Enum.find(clubs, &(&1.id == group.club_id)) || {:error, :not_found} do
      {:ok, club,
       %{
         type: "channel",
         id: group.id,
         author_id: group.created_by_id,
         club_id: club.id,
         channel_id: group.id
       }}
    else
      {:error, _reason} = error -> error
      _other -> {:error, :not_found}
    end
  end

  defp target(context, "partner", id), do: Partners.report_target(context, id)

  defp target(_context, _type, _id), do: {:error, :invalid_target}

  defp apply_action(_context, _type, _id, "dismiss"), do: :ok

  defp apply_action(context, "post", id, "hide"), do: done(CommunityPosts.hide(context, id, true))
  defp apply_action(context, "post", id, "delete"), do: done(CommunityPosts.delete(context, id))

  defp apply_action(context, "comment", id, "hide"),
    do: done(CommunityPosts.hide_comment(context, id, true))

  defp apply_action(context, "comment", id, "delete"),
    do: done(CommunityPosts.delete_comment(context, id))

  defp apply_action(context, "channel", id, "archive"),
    do: done(CommunityGroups.archive(context, id))

  defp apply_action(context, "partner", id, "hide"), do: done(Partners.suspend(context, id))

  defp done(:ok), do: :ok
  defp done({:ok, _result}), do: :ok
  # Already gone: closing its reports is still right.
  defp done({:error, :not_found}), do: :ok
  defp done(error), do: error

  defp row(context, type, id, reports) do
    preview = preview(context, type, id)

    %{
      target_type: type,
      target_id: id,
      channel_id: reports |> List.first() |> Map.get(:channel_id),
      author_id:
        (preview && preview.author_id) || reports |> List.first() |> Map.get(:target_author_id),
      preview: preview && Map.delete(preview, :author_id),
      report_count: length(reports),
      reasons: reports |> Enum.frequencies_by(& &1.reason),
      notes: reports |> Enum.map(& &1.note) |> Enum.reject(&is_nil/1),
      first_reported_at: reports |> Enum.map(& &1.inserted_at) |> Enum.min(DateTime),
      last_reported_at: reports |> Enum.map(& &1.inserted_at) |> Enum.max(DateTime)
    }
  end

  defp preview(context, "post", id) do
    case Community.find_post(context, id) do
      {:ok, post} ->
        %{
          author_id: post.author_id,
          body: post.body,
          hidden: not is_nil(post.hidden_at),
          media_status: Map.get(post, :media_status) || "ready",
          media: MediaUrls.present_post_media(post.author_id, Map.get(post, :media) || [])
        }

      _gone ->
        nil
    end
  end

  defp preview(context, "comment", id) do
    case Community.get_comment(context, id) do
      %{} = comment ->
        %{author_id: comment.author_id, body: comment.body, hidden: not is_nil(comment.hidden_at)}

      nil ->
        nil
    end
  end

  defp preview(context, "channel", id) do
    case Community.get_channel(context, id) do
      %{kind: "member_group"} = group ->
        %{
          author_id: group.created_by_id,
          name: group.name,
          body: group.description,
          hidden: not is_nil(group.archived_at)
        }

      _gone ->
        nil
    end
  end

  defp preview(context, "partner", id), do: Partners.report_preview(context, id)

  defp present_row(row, people) do
    row
    |> Map.put(:author, row.author_id && CommunityPeople.person(people, row.author_id))
    |> Map.delete(:author_id)
  end

  defp staff_club(context) do
    with {:ok, club} <- ClubScope.gym_club(context) do
      if club.role == "staff", do: {:ok, club}, else: {:error, :forbidden}
    end
  end

  defp notify_staff(club, target, reason) do
    club.organization_id
    |> Organizations.list_staff_user_ids()
    |> Enum.each(fn staff_id ->
      Notifications.dispatch_event(:community_report_created, %{
        user_id: staff_id,
        organization_id: club.organization_id,
        club_id: club.id,
        target_type: target.type,
        target_id: target.id,
        reason: reason
      })
    end)
  end
end
