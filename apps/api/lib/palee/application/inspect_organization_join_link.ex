defmodule Palee.Application.InspectOrganizationJoinLink do
  alias Palee.Organizations

  def call(slug), do: Organizations.inspect_join_link(slug)
end
