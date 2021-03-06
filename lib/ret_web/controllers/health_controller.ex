defmodule RetWeb.HealthController do
  use RetWeb, :controller
  import Ecto.Query

  def index(conn, _params) do
    # Check database
    from(h in Ret.Hub, limit: 1) |> Ret.Repo.one!()

    # Check page cache
    true = Cachex.get(:page_chunks, {:hubs, "index.html"}) |> elem(1) |> Enum.count() > 0
    true = Cachex.get(:page_chunks, {:hubs, "hub.html"}) |> elem(1) |> Enum.count() > 0
    true = Cachex.get(:page_chunks, {:spoke, "index.html"}) |> elem(1) |> Enum.count() > 0

    # Check room routing
    true = Ret.RoomAssigner.get_available_host("") != nil

    send_resp(conn, 200, "ok")
  end
end
