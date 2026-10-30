defmodule Palee.Application.RegisterProfile do
  @moduledoc """
  ADR-187: registration with an email. A new email creates a login and its
  first profile. An email that already has a login adds a profile to it, but
  only when the password matches that login's: the password is the proof the
  person owns those accounts. Otherwise the caller learns only how many
  profiles the email holds (never which), so the form can say "this email
  already has 2 of 3 accounts" without exposing them.

  ADR-211: an address a login changed away from in the last 7 days is held
  for it (`Identity.email_reserved_for_other?/1`): `{:error, :email_reserved}`,
  with nothing created.

  ADR-267: every sign-up confirms the minimum age (`age_confirmed: true`,
  `Identity.confirm_minimum_age/1`) before anything is looked up; a missing
  confirmation answers a field error and creates nothing. The time is kept on
  the login.
  """
  alias Palee.Application.PasswordVerifier
  alias Palee.Identity

  def call(params, now \\ DateTime.utc_now()) when is_map(params) do
    # ADR-267: the minimum age is confirmed before anything is looked up.
    with :ok <- Identity.confirm_minimum_age(params),
         {:ok, profile} <- register(params) do
      :ok = Identity.record_age_confirmation(profile.login_id, now)
      {:ok, profile}
    end
  end

  defp register(params) do
    case Identity.find_login_by_email(value(params, :email)) do
      nil -> if_not_reserved(params, &create_login/1)
      login -> add_to_existing(login, params)
    end
  end

  defp create_login(params) do
    case Identity.create_login_with_profile(params) do
      # Lost a race with a registration of the same email: treat it as one.
      {:error, :email_taken} ->
        case Identity.find_login_by_email(value(params, :email)) do
          nil -> {:error, :email_taken}
          login -> add_to_existing(login, params)
        end

      result ->
        result
    end
  end

  defp if_not_reserved(params, fun) do
    if Identity.email_reserved_for_other?(value(params, :email)),
      do: {:error, :email_reserved},
      else: fun.(params)
  end

  defp add_to_existing(login, params) do
    password = value(params, :password)

    if is_binary(password) and PasswordVerifier.verify(password, login.password_hash) do
      case Identity.add_profile(login.id, params) do
        {:ok, profile} ->
          # The new profile is the one in use now; an email sign-in opens it.
          :ok = Identity.touch_last_used(login.id, profile.id)
          {:ok, profile}

        {:error, :profile_limit} ->
          {:error, {:profile_limit, %{profile_limit: Identity.max_profiles()}}}

        result ->
          result
      end
    else
      {:error,
       {:email_in_use,
        %{profile_count: login.profile_count, profile_limit: Identity.max_profiles()}}}
    end
  end

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
