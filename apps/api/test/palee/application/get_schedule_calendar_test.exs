defmodule Palee.Application.GetScheduleCalendarTest do
  use ExUnit.Case, async: true

  alias Palee.Application.GetScheduleCalendar

  test "rejects a malformed start_date as a bad request instead of crashing" do
    context = %{organization_id: Ecto.UUID.generate()}

    assert GetScheduleCalendar.call(context, nil, %{"start_date" => "2026-13-45"}) ==
             {:error, :bad_request}

    assert GetScheduleCalendar.call(context, nil, %{"start_date" => "not-a-date"}) ==
             {:error, :bad_request}
  end
end
