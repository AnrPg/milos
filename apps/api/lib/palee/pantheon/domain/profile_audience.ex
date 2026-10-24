defmodule Palee.Pantheon.Domain.ProfileAudience do
  @moduledoc """
  Who sees a PR on its owner's profile (ADR-196), apart from coaches (the
  ADR-139 ladder) and accounts granted every PR (ADR-129): `private`, the
  default (vision §4.5), or `followers`. Εγώ › PRs lists only the PRs on the
  profile and counts the rest as private.
  """

  @audiences ~w(private followers)

  def audiences, do: @audiences

  def validate(audience) when audience in @audiences, do: :ok
  def validate(_audience), do: {:error, :invalid_profile_audience}
end
