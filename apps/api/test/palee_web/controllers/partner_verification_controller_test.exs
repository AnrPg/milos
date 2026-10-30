defmodule PaleeWeb.PartnerVerificationControllerTest do
  @moduledoc """
  ADR-280 §5 over HTTP, as the RLS runtime role: the person's verification
  routes, the sponsor's side and the vendors' queue, with their error codes.
  """
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Community.Follow
  alias Palee.{Organizations, Repo}
  alias Palee.Partners.Verification
  alias Palee.TestSupport.{MemoryObjectStore, MemorySmsSender}

  setup %{conn: conn} do
    MemorySmsSender.start()
    MemoryObjectStore.start()

    people =
      bypass_rls(fn ->
        candidate = user_fixture()
        sponsor = user_fixture()
        vendor = user_fixture()
        {:ok, _vendor} = Organizations.grant_vendor(vendor.id)

        for {from, to} <- [{candidate, sponsor}, {sponsor, candidate}] do
          Repo.insert!(%Follow{
            user_id: from.id,
            target_type: "user",
            target_id: to.id,
            status: "active",
            accepted_at: DateTime.utc_now()
          })
        end

        Repo.insert!(%Verification{
          user_id: sponsor.id,
          method: "membership",
          status: "verified",
          verified_at: DateTime.utc_now()
        })

        %{candidate: candidate, sponsor: sponsor, vendor: vendor}
      end)

    Map.merge(people, %{conn: conn, as: fn user -> put_bearer_token(conn, user) end})
  end

  defp send_json(conn, method, path, body \\ %{}) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  test "a person without a membership needs verification", ctx do
    body = ctx.as.(ctx.candidate) |> get("/api/me/partners/verification") |> json_response(200)

    assert %{"eligibility" => %{"status" => "needs_verification", "next_step" => "consent"}} =
             body

    assert body["request"] == nil
  end

  test "consent, ask a Buddy, the Buddy vouches", ctx do
    assert %{"request" => %{"selfie_code" => code, "status" => "collecting"}} =
             ctx.as.(ctx.candidate)
             |> send_json(:post, "/api/me/partners/verification/consent")
             |> json_response(200)

    assert code =~ ~r/^[0-9]{4}$/

    assert %{"candidates" => [%{"eligible" => true}]} =
             ctx.as.(ctx.candidate)
             |> get("/api/me/partners/verification/sponsor-candidates")
             |> json_response(200)

    assert %{"sponsorship" => %{"status" => "requested"}} =
             ctx.as.(ctx.candidate)
             |> send_json(:post, "/api/me/partners/verification/sponsors", %{
               sponsor_id: ctx.sponsor.id
             })
             |> json_response(200)

    assert %{"requests" => [%{"id" => id}], "vouching" => %{"can_vouch" => true, "left" => 5}} =
             ctx.as.(ctx.sponsor) |> get("/api/me/partners/vouch-requests") |> json_response(200)

    assert %{"status" => "vouched"} =
             ctx.as.(ctx.sponsor)
             |> send_json(:post, "/api/me/partners/vouch-requests/#{id}", %{decision: "vouch"})
             |> json_response(200)

    assert %{"used" => 1, "left" => 4} =
             ctx.as.(ctx.sponsor) |> get("/api/me/partners/vouching") |> json_response(200)
  end

  test "error codes of the phone step", ctx do
    ctx.as.(ctx.candidate)
    |> send_json(:post, "/api/me/partners/verification/consent")
    |> json_response(200)

    assert %{"code" => "partner_phone_invalid"} =
             ctx.as.(ctx.candidate)
             |> send_json(:post, "/api/me/partners/verification/phone", %{phone: "2101234567"})
             |> json_response(422)

    assert %{"code" => "partner_code_invalid"} =
             ctx.as.(ctx.candidate)
             |> send_json(:post, "/api/me/partners/verification/phone/confirm", %{code: "123456"})
             |> json_response(422)

    assert %{"code" => "document_key_forbidden"} =
             ctx.as.(ctx.candidate)
             |> send_json(:post, "/api/me/partners/verification/submit", %{
               file_key: "users/#{ctx.candidate.id}/partner-verification/other.jpg"
             })
             |> json_response(403)

    %{"file_key" => key} =
      ctx.as.(ctx.candidate)
      |> send_json(:post, "/api/me/partners/verification/selfie/upload-url", %{
        content_type: "image/jpeg"
      })
      |> json_response(200)

    assert %{"code" => "partner_verification_incomplete"} =
             ctx.as.(ctx.candidate)
             |> send_json(:post, "/api/me/partners/verification/submit", %{file_key: key})
             |> json_response(409)
  end

  test "a link is single use", ctx do
    ctx.as.(ctx.candidate)
    |> send_json(:post, "/api/me/partners/verification/consent")
    |> json_response(200)

    %{"token" => token} =
      ctx.as.(ctx.candidate)
      |> send_json(:post, "/api/me/partners/verification/link")
      |> json_response(201)

    assert %{"can_vouch" => true} =
             ctx.as.(ctx.sponsor)
             |> send_json(:post, "/api/me/partners/vouch-links/inspect", %{token: token})
             |> json_response(200)

    assert %{"status" => "vouched"} =
             ctx.as.(ctx.sponsor)
             |> send_json(:post, "/api/me/partners/vouch-links/vouch", %{token: token})
             |> json_response(200)

    assert %{"code" => "partner_link_expired"} =
             ctx.as.(ctx.sponsor)
             |> send_json(:post, "/api/me/partners/vouch-links/vouch", %{token: token})
             |> json_response(410)
  end

  test "the platform queue is for vendors only", ctx do
    assert %{"code" => "vendor_required"} =
             ctx.as.(ctx.candidate)
             |> get("/api/platform/partner-verifications")
             |> json_response(403)

    assert %{"requests" => []} =
             ctx.as.(ctx.vendor)
             |> get("/api/platform/partner-verifications")
             |> json_response(200)

    assert %{"code" => "partner_decision_reason_required"} =
             ctx.as.(ctx.vendor)
             |> send_json(
               :post,
               "/api/platform/partner-verifications/#{Ecto.UUID.generate()}/decision",
               %{
                 decision: "reject"
               }
             )
             |> json_response(422)
  end
end
