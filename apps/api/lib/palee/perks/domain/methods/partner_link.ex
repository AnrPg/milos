defmodule Palee.Perks.Domain.Methods.PartnerLink do
  @moduledoc """
  An online store link (ADR-191 §2). `link_url` is https; a `{code}` in it
  is replaced by the code (URL-encoded) so the store applies it, and then
  `shared_code` is required. Without `{code}` the link is the offer itself.
  """
  @behaviour Palee.Perks.Domain.RedemptionMethod

  @placeholder "{code}"

  @impl true
  def key, do: "partner_link"

  @impl true
  def validate(settings) do
    url = Map.get(settings, :link_url)
    code = Map.get(settings, :shared_code)

    cond do
      not (is_binary(url) and url =~ ~r/^https:\/\/[^\s]+$/i) ->
        [link_url: "must be an https link"]

      String.contains?(url, @placeholder) and not (is_binary(code) and code != "") ->
        [shared_code: "is needed for {code} in the link"]

      true ->
        []
    end
  end

  @impl true
  def issue, do: :shared
  @impl true
  def verifiable?, do: false
  @impl true
  def ready(_facts), do: :ok

  @impl true
  def reveal(settings, code) do
    url = Map.get(settings, :link_url)
    shown = if is_binary(Map.get(settings, :shared_code)), do: code

    %{
      code: shown,
      url: url && String.replace(url, @placeholder, URI.encode_www_form(code || "")),
      show_membership: false
    }
  end
end
