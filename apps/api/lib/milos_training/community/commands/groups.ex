defmodule MilosTraining.Community.Commands.Groups do
  @moduledoc """
  Member groups in a gym's club (ADR-143): proposing one, staff deciding,
  joining and leaving, admins letting people in and handing over, and the
  quiet-group lifecycle. Governance comes from `GroupPolicy`; the caller
  states the actor's club role and their membership of the group.
  """

  alias MilosTraining.Community.{CommunitySettings, CommunityStore}
  alias MilosTraining.Community.Domain.GroupPolicy

  def settings(context), do: CommunityStore.get_community_settings(context)

  def put_settings(context, attrs) do
    attrs =
      attrs |> Map.take(CommunitySettings.fields()) |> Map.reject(fn {_k, v} -> is_nil(v) end)

    cond do
      attrs == %{} ->
        {:error, :invalid_member_groups}

      Map.has_key?(attrs, :member_groups) and
          attrs.member_groups not in CommunitySettings.member_group_options() ->
        {:error, :invalid_member_groups}

      Map.has_key?(attrs, :partners_enabled) and not is_boolean(attrs.partners_enabled) ->
        {:error, :invalid_partners_enabled}

      true ->
        CommunityStore.put_community_settings(context, attrs)
    end
  end

  def propose(%{user_id: user_id} = context, club, role, attrs) do
    setting = settings(context).member_groups

    if GroupPolicy.can_propose?(role, setting) do
      status = GroupPolicy.initial_status(role, setting)
      CommunityStore.create_group(context, club, GroupPolicy.channel_spec(attrs), user_id, status)
    else
      {:error, :member_groups_disabled}
    end
  end

  def list(context, club_id, filter \\ %{}),
    do: CommunityStore.list_groups(context, club_id, filter)

  def members(context, group_id), do: CommunityStore.list_channel_memberships(context, group_id)

  def decide(%{user_id: user_id} = context, group, role, decision, now)
      when decision in ["approve", "decline"] do
    if GroupPolicy.can_decide?(group, role) do
      CommunityStore.update_group_lifecycle(context, group.id, %{
        status: if(decision == "approve", do: "active", else: "declined"),
        decided_by_id: user_id,
        decided_at: now
      })
    else
      {:error, :forbidden}
    end
  end

  def decide(_context, _group, _role, _decision, _now), do: {:error, :invalid_decision}

  @doc "Joining an open group lets you in; a group that asks records a request."
  def join(%{user_id: user_id} = context, group, membership) do
    cond do
      not GroupPolicy.live?(group) ->
        {:error, :group_not_open}

      member?(membership) ->
        {:ok, membership.source}

      true ->
        source = GroupPolicy.join_source(group)

        with :ok <-
               CommunityStore.put_channel_membership(context, group, user_id, %{source: source}),
             do: {:ok, source}
    end
  end

  @doc "Leaving; the last member archives the group, the last admin hands over first."
  def leave(%{user_id: user_id} = context, group, membership, now) do
    members = members(context, group.id) |> Enum.filter(&member?/1)
    admins = Enum.count(members, &(&1.role == "admin"))

    case GroupPolicy.on_leave(membership || %{role: "member"}, admins, length(members)) do
      {:error, _reason} = error ->
        error

      :archive ->
        with :ok <- dismiss(context, group, user_id),
             {:ok, _group} <-
               CommunityStore.update_group_lifecycle(context, group.id, %{archived_at: now}),
             do: {:ok, :archived}

      :leave ->
        with :ok <- dismiss(context, group, user_id), do: {:ok, :left}
    end
  end

  @doc "An admin (or staff) lets a requester in, or turns them away."
  def answer_request(context, group, actor, user_id, approve?) do
    with :ok <- manage(actor),
         %{source: "requested"} <- find_member(context, group.id, user_id) || {:error, :not_found} do
      source = if approve?, do: "invited", else: "dismissed"
      CommunityStore.put_channel_membership(context, group, user_id, %{source: source})
    end
  end

  @doc "An admin (or staff) makes a member an admin, or an admin a member again."
  def set_admin(context, group, actor, user_id, admin?) do
    with :ok <- manage(actor),
         %{} = membership <- find_member(context, group.id, user_id) || {:error, :not_found},
         true <- member?(membership) || {:error, :not_found} do
      CommunityStore.put_channel_membership(context, group, user_id, %{
        source: membership.source,
        role: if(admin?, do: "admin", else: "member")
      })
    end
  end

  def remove_member(context, group, actor, user_id) do
    with :ok <- manage(actor),
         %{} <- find_member(context, group.id, user_id) || {:error, :not_found},
         do: dismiss(context, group, user_id)
  end

  def update(context, group, actor, attrs) do
    with :ok <- manage(actor),
         do:
           CommunityStore.update_group(
             context,
             group.id,
             Map.take(attrs, [:name, :description, :join_policy])
           )
  end

  def archive(context, group, actor, now) do
    with :ok <- manage(actor),
         do: CommunityStore.update_group_lifecycle(context, group.id, %{archived_at: now})
  end

  @doc """
  Its creator or staff bring an archived group back; it counts as active
  from now. A group nobody runs any more gets whoever reopened it as admin.
  """
  def reopen(%{user_id: user_id} = context, group, club_role, now) do
    if GroupPolicy.can_reopen?(group, club_role, user_id) do
      with {:ok, reopened} <-
             CommunityStore.update_group_lifecycle(context, group.id, %{
               archived_at: nil,
               archive_warned_at: nil,
               last_post_at: now
             }),
           :ok <- ensure_admin(context, group, user_id),
           do: {:ok, reopened}
    else
      {:error, :forbidden}
    end
  end

  defp ensure_admin(context, group, user_id) do
    if context |> members(group.id) |> Enum.any?(&(member?(&1) and &1.role == "admin")),
      do: :ok,
      else:
        CommunityStore.put_channel_membership(context, group, user_id, %{
          source: "auto",
          role: "admin"
        })
  end

  def quiet_groups(context, now),
    do: CommunityStore.quiet_groups(context, GroupPolicy.warn_cutoff(now))

  def mark_warned(context, group, now),
    do: CommunityStore.update_group_lifecycle(context, group.id, %{archive_warned_at: now})

  def member?(%{source: source}), do: source in ~w(opt_in invited auto)
  def member?(_membership), do: false

  # `actor` is `%{club_role: _, membership: _}`.
  defp manage(%{club_role: club_role, membership: membership}) do
    role = if member?(membership), do: membership.role, else: nil
    if GroupPolicy.can_manage?(role, club_role), do: :ok, else: {:error, :forbidden}
  end

  defp find_member(context, group_id, user_id),
    do: context |> members(group_id) |> Enum.find(&(&1.user_id == user_id))

  defp dismiss(context, group, user_id),
    do: CommunityStore.put_channel_membership(context, group, user_id, %{source: "dismissed"})
end
