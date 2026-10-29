defmodule Palee.Identity.Domain.AgePolicy do
  @moduledoc """
  ADR-267: the minimum age to hold a Palee account.

  Sign-up asks the person to confirm that they are at least
  `minimum_age/0` years old (`age_confirmed: true`) instead of asking for a
  date of birth: Palee needs only the yes/no, never the date (data
  minimisation, GDPR article 5(1)(c)), and the data inventory keeps "Date of
  birth" under "not collected". The confirmation is enforced here, not only
  in the form, and its time is kept on the login as evidence.
  """

  @minimum_age 16

  @doc "The youngest age that may hold an account."
  def minimum_age, do: @minimum_age

  @doc """
  `:ok` when the sign-up confirms the minimum age, otherwise the field error
  the sign-up form shows under the confirmation.
  """
  def confirm(params) when is_map(params) do
    if confirmed?(value(params)),
      do: :ok,
      else: {:error, {:invalid_fields, %{"age_confirmed" => "minimum_age"}}}
  end

  def confirm(_params), do: {:error, {:invalid_fields, %{"age_confirmed" => "minimum_age"}}}

  defp confirmed?(value), do: value in [true, "true"]

  defp value(params), do: Map.get(params, :age_confirmed, Map.get(params, "age_confirmed"))
end
