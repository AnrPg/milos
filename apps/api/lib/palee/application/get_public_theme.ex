defmodule Palee.Application.GetPublicTheme do
  @moduledoc """
  The public UI theme (unauthenticated: login page and app shell).

  TD-092: the theme is a per-gym gamification setting, a tenant row. The
  request carries no tenant scope, so the gym is named by its public slug
  (the web client sends it as `X-Organization-Slug`) and only its theme slug
  is read, through a narrow SECURITY DEFINER helper. Without a known gym the
  default theme applies.
  """

  alias Palee.Gamification

  @default_theme "ember"

  def call(organization_slug \\ nil)

  def call(organization_slug) when is_binary(organization_slug) and organization_slug != "" do
    {:ok, %{theme_slug: Gamification.public_theme_slug(organization_slug) || @default_theme}}
  end

  def call(_organization_slug), do: {:ok, %{theme_slug: @default_theme}}
end
