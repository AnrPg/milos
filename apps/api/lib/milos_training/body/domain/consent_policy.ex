defmodule MilosTraining.Body.Domain.ConsentPolicy do
  @moduledoc """
  Health consents (ADR-158, plan D8): an explicit record before the first
  body photo. A grant is a row; withdrawing closes it, and a later grant
  opens a new one, so the history stays.

  - Uploading or attaching a body photo needs an active `body_photos` grant.
  - Withdrawing hides every photo from coaches at once (the database checks
    the consent on each coach read); the person still sees their own.
  - `health_data` is recorded for the wellness sections (P2-M11).
  """

  @scopes ~w(body_photos health_data)

  def scopes, do: @scopes

  def validate_scope(scope) when scope in @scopes, do: :ok
  def validate_scope(_scope), do: {:error, :invalid_consent_scope}

  @doc "Whether any of `consents` is an active grant of `scope`."
  def active?(consents, scope) when is_list(consents),
    do: Enum.any?(consents, &(&1.scope == scope and is_nil(&1.withdrawn_at)))

  @doc "Requires an active body-photo grant."
  def require_photos(consents),
    do:
      if(active?(consents, "body_photos"), do: :ok, else: {:error, :body_photo_consent_required})

  @doc "Whether a coach may see a snapshot's photos."
  def photos_visible_to_coach?(visibility, consent_active?),
    do: visibility == "coach_full" and consent_active? == true

  @doc "One entry per scope: active or not, and the latest grant's dates."
  def summary(consents) when is_list(consents) do
    Enum.map(@scopes, fn scope ->
      latest =
        consents
        |> Enum.filter(&(&1.scope == scope))
        |> Enum.max_by(& &1.granted_at, DateTime, fn -> nil end)

      %{
        scope: scope,
        active: active?(consents, scope),
        granted_at: latest && latest.granted_at,
        withdrawn_at: latest && latest.withdrawn_at
      }
    end)
  end
end
