defmodule Palee.Application.SuggestBoxTag do
  @moduledoc """
  Board 3b Q5: an owner suggests a tag missing from a canonical list. It is
  queued for platform review and never shows on the page by itself; free
  text tags would break filters and translations.
  """

  alias Palee.Organizations

  def call(context, params) when is_map(params) do
    with :ok <- Organizations.authorize_capability(context, :manage_settings) do
      Organizations.create_tag_suggestion(context, %{
        "suggested_by_id" => Map.get(context, :user_id),
        "list" => params["list"] || params[:list],
        "name" => params["name"] || params[:name]
      })
    end
  end

  @doc "Pending suggestions from every gym, for platform staff."
  def pending, do: Organizations.pending_tag_suggestions()

  @doc "Platform staff mark a suggestion `added` (now in the list) or `declined`."
  def resolve(id, status) when status in ["added", "declined"],
    do: Organizations.resolve_tag_suggestion(id, status)

  def resolve(_id, _status), do: {:error, :invalid_status}
end
