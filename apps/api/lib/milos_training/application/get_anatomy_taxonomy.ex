defmodule MilosTraining.Application.GetAnatomyTaxonomy do
  @moduledoc """
  The static, code-owned anatomy taxonomy for clients (ADR-163): version,
  nodes, fitness qualities and goal roles, with a strong ETag derived from
  the content so clients and proxies can cache it until the code changes.
  """

  alias MilosTraining.Anatomy

  @taxonomy Anatomy.taxonomy()
  @etag ~s("anatomy-v#{@taxonomy.version}-) <>
          (:crypto.hash(:sha256, :erlang.term_to_binary(@taxonomy))
           |> Base.url_encode64(padding: false)
           |> binary_part(0, 16)) <> ~s(")

  def call, do: {:ok, @taxonomy, @etag}
end
