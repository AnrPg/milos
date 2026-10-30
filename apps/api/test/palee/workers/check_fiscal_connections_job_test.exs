defmodule Palee.Workers.CheckFiscalConnectionsJobTest do
  @moduledoc """
  ADR-273: the scheduled «Δοκιμή σύνδεσης». Only due connections are
  checked; one that becomes invalid notifies the staff who manage billing,
  once, with a link to the connection.
  """

  use PaleeWeb.ConnCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Palee.TestFixtures

  alias Palee.{Organizations, Repo}
  alias Palee.Workers.CheckFiscalConnectionsJob

  setup %{conn: conn} do
    owner = admin_fixture(%{nickname: "job_owner"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Check job #{System.unique_integer([:positive])}"
      })

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    owner_conn = put_bearer_token(conn, owner)
    admin = "/api/org/#{organization.slug}/admin/fiscal"

    owner_conn
    |> put_req_header("content-type", "application/json")
    |> put(
      "#{admin}/identity",
      Jason.encode!(%{
        "legal_name" => "CrossFit Αθήνα ΙΚΕ",
        "country_code" => "GR",
        "tax_id" => "090000045",
        "tax_office" => "Α' Αθηνών",
        "street" => "Ερμού",
        "postal_code" => "10563",
        "city" => "Αθήνα"
      })
    )
    |> json_response(200)

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      Plug.Conn.send_resp(conn, 200, "<RequestedDoc/>")
    end)

    assert %{"connection" => %{"status" => "active"}} =
             owner_conn
             |> recycle()
             |> put_req_header("content-type", "application/json")
             |> put(
               "#{admin}/authority-connection",
               Jason.encode!(%{
                 "environment" => "test",
                 "user_id" => "boxuser",
                 "subscription_key" => "secret-key"
               })
             )
             |> json_response(200)

    %{organization: organization, owner: owner}
  end

  defp make_due(organization) do
    Repo.query!(
      "UPDATE fiscal_authority_connections SET next_check_at = now() - interval '1 minute' WHERE organization_id = $1",
      [Ecto.UUID.dump!(organization.id)]
    )
  end

  defp status(organization) do
    %{rows: [[status, code]]} =
      Repo.query!(
        "SELECT status, error_code FROM fiscal_authority_connections WHERE organization_id = $1 AND authority = 'mydata'",
        [Ecto.UUID.dump!(organization.id)]
      )

    {status, code}
  end

  defp notices(owner) do
    %{rows: rows} =
      Repo.query!(
        "SELECT payload FROM notifications WHERE user_id = $1 AND type = 'fiscal_connection_failed'",
        [Ecto.UUID.dump!(owner.id)]
      )

    Enum.map(rows, &hd/1)
  end

  test "a connection that is not due is left alone", ctx do
    Req.Test.stub(Palee.FiscalHttp, fn conn -> Plug.Conn.send_resp(conn, 401, "denied") end)

    assert :ok =
             perform_job(CheckFiscalConnectionsJob, %{"organization_id" => ctx.organization.id})

    assert status(ctx.organization) == {"active", nil}
    assert notices(ctx.owner) == []
  end

  test "a due connection AADE refuses becomes invalid and the owner hears it once", ctx do
    make_due(ctx.organization)
    Req.Test.stub(Palee.FiscalHttp, fn conn -> Plug.Conn.send_resp(conn, 401, "denied") end)

    assert :ok =
             perform_job(CheckFiscalConnectionsJob, %{"organization_id" => ctx.organization.id})

    assert status(ctx.organization) == {"invalid", "credentials_rejected"}

    assert [
             %{
               "connection" => "myDATA",
               "error_code" => "credentials_rejected",
               "url" => "/admin/settings/billing?connection=mydata"
             }
           ] = notices(ctx.owner)

    # Still refused on the next check: no second notice.
    make_due(ctx.organization)

    assert :ok =
             perform_job(CheckFiscalConnectionsJob, %{"organization_id" => ctx.organization.id})

    assert length(notices(ctx.owner)) == 1

    # Accepted again: active, without a notice.
    make_due(ctx.organization)

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      Plug.Conn.send_resp(conn, 200, "<RequestedDoc/>")
    end)

    assert :ok =
             perform_job(CheckFiscalConnectionsJob, %{"organization_id" => ctx.organization.id})

    assert status(ctx.organization) == {"active", nil}
    assert length(notices(ctx.owner)) == 1
  end

  test "an unreachable AADE changes nothing and notifies nobody", ctx do
    make_due(ctx.organization)
    Req.Test.stub(Palee.FiscalHttp, fn conn -> Plug.Conn.send_resp(conn, 503, "busy") end)

    assert :ok =
             perform_job(CheckFiscalConnectionsJob, %{"organization_id" => ctx.organization.id})

    assert status(ctx.organization) == {"active", "unreachable"}
    assert notices(ctx.owner) == []
  end

  test "the hourly sweep runs over every active box", ctx do
    make_due(ctx.organization)
    Req.Test.stub(Palee.FiscalHttp, fn conn -> Plug.Conn.send_resp(conn, 401, "denied") end)

    assert :ok = perform_job(CheckFiscalConnectionsJob, %{})
    assert status(ctx.organization) == {"invalid", "credentials_rejected"}
  end
end
