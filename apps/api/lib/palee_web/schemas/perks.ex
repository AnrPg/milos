defmodule PaleeWeb.Schemas.Perks do
  @moduledoc """
  OpenAPI schemas for partner perks (ADR-191). The documents and the perk
  and claim shapes are named components, referenced by every response that
  carries them; the bodies live in `PaleeWeb.Schemas.PerkParts`.
  """

  alias PaleeWeb.Schemas.PerkParts, as: P

  defmodule Benefit do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(
      Map.from_struct(PaleeWeb.Schemas.PerkParts.benefit("PerkBenefit", [:type])),
      struct?: false
    )
  end

  defmodule Rules do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(Map.from_struct(PaleeWeb.Schemas.PerkParts.rules("PerkRules")),
      struct?: false
    )
  end

  defmodule Redemption do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(
      Map.from_struct(PaleeWeb.Schemas.PerkParts.redemption("PerkRedemptionSettings")),
      struct?: false
    )
  end

  defmodule PerkVersion do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(Map.from_struct(PaleeWeb.Schemas.PerkParts.version_item()), struct?: false)
  end

  defmodule StaffPerk do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(Map.from_struct(PaleeWeb.Schemas.PerkParts.staff_perk()), struct?: false)
  end

  defmodule MemberPerkClaim do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(Map.from_struct(PaleeWeb.Schemas.PerkParts.member_claim()), struct?: false)
  end

  defmodule MemberPerk do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(Map.from_struct(PaleeWeb.Schemas.PerkParts.member_perk()), struct?: false)
  end

  defdelegate body(schema), to: P
  defdelegate status(), to: P
  defdelegate redemption_method(), to: P
  defdelegate claim_status(), to: P
  defdelegate staff_list(), to: P
  defdelegate staff_response(), to: P
  defdelegate versions_response(), to: P
  defdelegate perk_input(required \\ []), to: P
  defdelegate codes_input(), to: P
  defdelegate codes_response(), to: P
  defdelegate claims_export(), to: P
  defdelegate staff_claim_response(), to: P
  defdelegate member_list(), to: P
  defdelegate member_claims(), to: P
  defdelegate claim_response(), to: P
  defdelegate verification_response(), to: P
  defdelegate error(), to: P
end
