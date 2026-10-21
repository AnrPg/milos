defmodule Palee.Pantheon.Queries.ListPRAccessGrants do
  @moduledoc """
  Active PR sharing grants (ADR-129): `owned/1` for the owner's management
  view, `received/1` for the grantee's "Shared with me" view. RLS admits the
  owner to their own grants and the grantee to grants naming them.
  """

  alias Palee.Pantheon.PRStore

  def owned(user_id), do: PRStore.list_owned_grants(user_id)
  def received(grantee_user_id), do: PRStore.list_received_grants(grantee_user_id)
end
