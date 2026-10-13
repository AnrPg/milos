defmodule MilosTraining.Content.Domain.VideoPolicy do
  @moduledoc "Pure rules for on-demand video items (ADR-098)."

  @max_tags 8

  @doc "Videos are linked, never hosted: only absolute https URLs are accepted."
  def valid_url?(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> true
      _other -> false
    end
  end

  def valid_url?(_url), do: false

  def normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.map(&(&1 |> to_string() |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.take(@max_tags)
  end

  def normalize_tags(_tags), do: []

  @doc "Members see published, not archived videos."
  def visible_to_members?(%{published_at: published_at, archived_at: nil})
      when not is_nil(published_at),
      do: true

  def visible_to_members?(_video), do: false
end
