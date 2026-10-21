defmodule Palee.Repo.Migrations.AiSettingsVoiceLogging do
  @moduledoc """
  ADR-175 (P3-M13): voice logging gets its own switch in the gym's AI
  settings, off by default. Nothing else is stored: the audio lives in memory
  for one request and the draft is saved only through the normal training
  log once the member confirms it. The table keeps its forced RLS, policy
  and tenant trigger from ADR-174.
  """

  use Ecto.Migration

  def change do
    alter table(:organization_ai_settings) do
      add :voice_enabled, :boolean, null: false, default: false
    end
  end
end
