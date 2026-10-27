defmodule Palee.Identity.Domain.AccountDeletionPolicy do
  @moduledoc """
  ADR-211: the rules of self-service account deletion, as pure decisions.

  - A request is for the current profile (`:profile`) or for the login with
    all its profiles (`:login`). Deleting a login's only profile is deleting
    the login.
  - It needs the login's password. A verified email then confirms it by
    link (24 h); without a verified email the person types the email
    address instead, since an emailed link could not prove more.
  - Once confirmed it waits `grace_days/0` days, during which it can be
    undone, then runs.
  """

  @grace_days 7
  @scopes %{"profile" => :profile, "login" => :login}

  def grace_days, do: @grace_days

  @doc "When a deletion confirmed at `now` runs."
  def scheduled_for(%DateTime{} = now), do: DateTime.add(now, @grace_days * 86_400, :second)

  @doc "`{:ok, :profile | :login}` from the request's `scope`."
  def scope(scope) when is_atom(scope) and not is_nil(scope), do: scope(Atom.to_string(scope))

  def scope(scope) when is_binary(scope) do
    case Map.fetch(@scopes, scope) do
      {:ok, scope} -> {:ok, scope}
      :error -> {:error, :invalid_scope}
    end
  end

  def scope(_scope), do: {:error, :invalid_scope}

  @doc "The scope that takes effect: a login's last profile takes the login with it."
  def effective_scope(:profile, profile_count) when profile_count <= 1, do: :login
  def effective_scope(scope, _profile_count), do: scope

  @doc "The profiles a request deletes, from the login's profile ids."
  def profile_ids(:login, _current_id, login_profile_ids), do: login_profile_ids
  def profile_ids(:profile, current_id, _login_profile_ids), do: [current_id]

  @doc "Whether the request is confirmed by an emailed link (a verified address) or by typing."
  def confirmation(%{email_verified_at: %DateTime{}}), do: :email_link
  def confirmation(_account), do: :typed_email

  @doc "Whether what the person typed is the login's email (case and outer spaces ignored)."
  def typed_email_matches?(typed, email) when is_binary(typed) and is_binary(email),
    do: normalize(typed) == normalize(email)

  def typed_email_matches?(_typed, _email), do: false

  @doc "Whether a scheduled deletion covers the profile `user_id` of `login_id`."
  def covers?(%{status: :scheduled, scope: :login, login_id: login_id}, %{login_id: login_id}),
    do: true

  def covers?(%{status: :scheduled, scope: :profile, user_id: user_id}, %{id: user_id}), do: true
  def covers?(_deletion, _account), do: false

  @doc "Whether the grace of a scheduled deletion is over at `now`."
  def due?(%{status: :scheduled, scheduled_for: %DateTime{} = at}, %DateTime{} = now),
    do: DateTime.compare(at, now) != :gt

  def due?(_deletion, _now), do: false

  defp normalize(value), do: value |> String.trim() |> String.downcase()
end
