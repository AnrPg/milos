defmodule Palee.Infrastructure.Identity.EctoAccountDeletionStore do
  @moduledoc "Ecto adapter of `Palee.Identity.Ports.AccountDeletionStore` (ADR-211)."
  @behaviour Palee.Identity.Ports.AccountDeletionStore

  import Ecto.Query

  alias Palee.Identity.{AccountDeletion, Login, PasswordHasher, User}
  alias Palee.Repo

  # What an anonymised profile shows wherever a business record still names
  # it (an invoice list, a ledger). Not a translation key: the stored row is
  # the same in every language, and it says nothing about the person.
  @anonymous_name "Deleted account"

  @impl true
  def for_login(login_id),
    do: AccountDeletion |> where([d], d.login_id == ^login_id) |> Repo.one()

  @impl true
  def get(id), do: Repo.get(AccountDeletion, id)

  @impl true
  def open(attrs) do
    Repo.transaction(fn ->
      existing =
        AccountDeletion
        |> where([d], d.login_id == ^attrs.login_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      case existing do
        %AccountDeletion{status: :scheduled} ->
          Repo.rollback(:already_scheduled)

        %AccountDeletion{} = awaiting ->
          Repo.delete!(awaiting)

        nil ->
          :ok
      end

      %AccountDeletion{}
      |> Ecto.Changeset.change(attrs)
      |> Repo.insert!()
    end)
  end

  @impl true
  def schedule(id, now, scheduled_for) do
    Repo.transaction(fn ->
      case AccountDeletion |> where([d], d.id == ^id) |> lock("FOR UPDATE") |> Repo.one() do
        nil ->
          Repo.rollback(:not_found)

        %AccountDeletion{status: :scheduled} ->
          Repo.rollback(:already_scheduled)

        deletion ->
          deletion
          |> Ecto.Changeset.change(
            status: :scheduled,
            confirmed_at: now,
            scheduled_for: scheduled_for
          )
          |> Repo.update!()
      end
    end)
  end

  @impl true
  def delete(id) do
    AccountDeletion |> where([d], d.id == ^id) |> Repo.delete_all()
    :ok
  end

  @impl true
  def due(now, limit) do
    AccountDeletion
    |> where([d], d.status == :scheduled and d.scheduled_for <= ^now)
    |> order_by([d], asc: d.scheduled_for, asc: d.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @impl true
  def sole_owned_organizations([]), do: []

  def sole_owned_organizations(user_ids) when is_list(user_ids) do
    ids = Enum.map(user_ids, &Ecto.UUID.dump!/1)

    Repo.query!(
      "SELECT organization_id, organization_name FROM palee_sole_owned_organizations($1) ORDER BY organization_name",
      [ids]
    ).rows
    |> Enum.map(fn [id, name] -> %{id: Ecto.UUID.load!(id), name: name} end)
  end

  @impl true
  def has_retained_records?(user_id) do
    %{rows: [[retained?]]} =
      Repo.query!("SELECT palee_user_has_retained_records($1)", [Ecto.UUID.dump!(user_id)])

    retained?
  end

  @impl true
  def anonymize_profile(user_id) do
    Repo.transaction(fn ->
      case User |> where([u], u.id == ^user_id) |> lock("FOR UPDATE") |> Repo.one() do
        nil -> Repo.rollback(:not_found)
        user -> anonymize(user)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete_login_if_empty(login_id) do
    unless User |> where([u], u.login_id == ^login_id) |> Repo.exists?() do
      Login |> where([l], l.id == ^login_id) |> Repo.delete_all()
    end

    :ok
  end

  # ADR-280: Partners rows are the person's own and leave with the account
  # even when the profile itself is kept anonymised (a deleted user row
  # takes them by cascade).
  @partner_rows [
    {"partner_reports", ~w(reporter_id target_id)},
    {"partner_matches", ~w(user_a_id user_b_id)},
    {"partner_swipes", ~w(swiper_id target_id)},
    {"partner_profiles", ~w(user_id)}
  ]

  defp delete_partner_rows(user_id) do
    id = Ecto.UUID.dump!(user_id)

    for {table, columns} <- @partner_rows do
      condition = Enum.map_join(columns, " OR ", &"#{&1} = $1")
      Repo.query!("DELETE FROM #{table} WHERE #{condition}", [id])
    end

    :ok
  end

  defp anonymize(%User{} = user) do
    # A login of its own: the person's login (and email) can go, and nobody
    # knows this one's address or password.
    tombstone =
      Repo.insert!(%Login{
        email: "deleted+#{user.id}@deleted.invalid",
        password_hash: PasswordHasher.hash(Base.encode64(:crypto.strong_rand_bytes(32))),
        security_version: 0
      })

    Login
    |> where([l], l.id == ^user.login_id and l.last_used_user_id == ^user.id)
    |> Repo.update_all(set: [last_used_user_id: nil])

    "handle_reservations"
    |> where([r], r.user_id == ^Ecto.UUID.dump!(user.id))
    |> Repo.delete_all()

    delete_partner_rows(user.id)

    user
    |> Ecto.Changeset.change(
      handle: "deleted." <> Base.encode16(:crypto.strong_rand_bytes(5), case: :lower),
      display_name: @anonymous_name,
      search_text: "",
      handle_changed_at: nil,
      avatar_url: nil,
      time_zone: nil,
      preferred_theme_slug: nil,
      completed_tours: [],
      login_id: tombstone.id,
      security_version: (user.security_version || 1) + 1,
      calendar_feed_token_version: (user.calendar_feed_token_version || 1) + 1
    )
    |> Repo.update!()

    :ok
  end
end
