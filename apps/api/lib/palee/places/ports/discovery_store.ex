defmodule Palee.Places.Ports.DiscoveryStore do
  @moduledoc """
  Cross-gym discovery of public items near a place (ADR-154). Answers carry
  ids, public coordinates and distances in metres; the cards are read
  elsewhere, through the usual policies. `area` is a `SearchArea`, `plan`
  an `AroundPlan`.
  """

  @type kind :: String.t()
  @type row :: map()

  @callback search(
              context :: map(),
              kind(),
              area :: map(),
              plan :: map(),
              cursor :: map() | nil,
              limit :: pos_integer()
            ) :: {[row()], non_neg_integer()}

  @callback counts(context :: map(), area :: map(), plan :: map(), radii_m :: [float()]) ::
              %{kind() => %{float() => non_neg_integer()}}

  @callback pins(context :: map(), area :: map(), plan :: map(), limit :: pos_integer()) :: [
              row()
            ]
end
