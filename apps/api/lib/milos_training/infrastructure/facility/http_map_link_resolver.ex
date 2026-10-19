defmodule MilosTraining.Infrastructure.Facility.HttpMapLinkResolver do
  @moduledoc """
  Expands short Google Maps links by following their redirects one hop at a
  time (ADR-141). Every hop must stay on a Google Maps host, so a pasted link
  can never make the API fetch anything else.
  """

  @behaviour MilosTraining.Application.Ports.MapLinkResolver

  alias MilosTraining.Facility.Domain.MapLink

  @max_hops 4

  @impl true
  def expand(url), do: follow(url, @max_hops)

  defp follow(_url, 0), do: {:error, :map_link_unresolved}

  defp follow(url, hops) do
    %URI{host: host} = URI.parse(url)

    cond do
      MapLink.long_host?(host) ->
        {:ok, url}

      MapLink.short_host?(host) ->
        case Req.get(url,
               redirect: false,
               retry: false,
               receive_timeout: 5_000,
               decode_body: false
             ) do
          {:ok, %Req.Response{status: status} = response} when status in 301..308 ->
            case Req.Response.get_header(response, "location") do
              [location | _] -> follow(URI.merge(url, location) |> URI.to_string(), hops - 1)
              [] -> {:error, :map_link_unresolved}
            end

          _other ->
            {:error, :map_link_unresolved}
        end

      true ->
        {:error, :map_link_unresolved}
    end
  end
end
