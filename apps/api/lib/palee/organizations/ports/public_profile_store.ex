defmodule Palee.Organizations.Ports.PublicProfileStore do
  @moduledoc "Persistence port of gym public profiles (ADR-142)."

  @callback get(context :: map()) :: map() | nil
  @callback upsert(context :: map(), params :: map()) :: {:ok, map()} | {:error, term()}
  @callback create_suggestion(context :: map(), params :: map()) ::
              {:ok, map()} | {:error, term()}
  @callback pending_suggestions() :: [map()]
  @callback resolve_suggestion(id :: String.t(), status :: String.t()) ::
              :ok | {:error, :not_found}

  # Visitors (no session): which published gym a slug or alias names, and the
  # public face of published gyms by id.
  @callback public_box_by_slug(slug :: String.t()) ::
              %{organization_id: String.t(), slug: String.t()} | nil
  @callback public_boxes(organization_ids :: [String.t()]) :: [map()]
  # ADR-216: published, live businesses whose name, brand name or slug holds
  # one of the folded `terms`, word starts first.
  @callback search_public_boxes(terms :: [String.t()], limit :: pos_integer()) :: [map()]
end
