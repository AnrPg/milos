defmodule Palee.Application.InspectOrganizationJoinLink do
  alias Palee.Organizations

  def call(link), do: Organizations.inspect_join_link(link)
end
