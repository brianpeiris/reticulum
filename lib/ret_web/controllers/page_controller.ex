defmodule RetWeb.PageController do
  use RetWeb, :controller
  alias Ret.{Repo, Hub, Scene, SceneListing, Avatar, AvatarListing, PageOriginWarmer}

  def call(conn, _params) do
    render_for_path(conn.request_path, conn.query_params, conn)
  end

  defp render_scene_content(%t{} = scene, conn) when t in [Scene, SceneListing] do
    scene_meta_tags =
      Phoenix.View.render_to_string(RetWeb.PageView, "scene-meta.html", scene: scene, ret_meta: Ret.Meta.get_meta())

    chunks =
      chunks_for_page("scene.html", :hubs)
      |> List.insert_at(1, scene_meta_tags)

    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_resp(200, chunks)
  end

  defp render_scene_content(nil, conn) do
    conn |> send_resp(404, "")
  end

  defp render_avatar_content(%t{} = avatar, conn) when t in [Avatar, AvatarListing] do
    avatar_meta_tags =
      Phoenix.View.render_to_string(RetWeb.PageView, "avatar-meta.html", avatar: avatar, ret_meta: Ret.Meta.get_meta())

    chunks =
      chunks_for_page("avatar.html", :hubs)
      |> List.insert_at(1, avatar_meta_tags)

    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_resp(200, chunks)
  end

  defp render_avatar_content(nil, conn) do
    conn |> send_resp(404, "")
  end

  def render_for_path("/", _params, conn), do: conn |> render_page("index.html")

  def render_for_path("/scenes/" <> path, _params, conn) do
    path
    |> String.split("/")
    |> Enum.at(0)
    |> Scene.scene_or_scene_listing_by_sid()
    |> Repo.preload([:screenshot_owned_file])
    |> render_scene_content(conn)
  end

  def render_for_path("/avatars/" <> path, _params, conn) do
    path
    |> String.split("/")
    |> Enum.at(0)
    |> Avatar.avatar_or_avatar_listing_by_sid()
    |> Repo.preload([:thumbnail_owned_file])
    |> render_avatar_content(conn)
  end

  def render_for_path("/link", _params, conn), do: conn |> render_page("link.html")
  def render_for_path("/link/", _params, conn), do: conn |> render_page("link.html")

  def render_for_path("/link/" <> hub_identifier_and_slug, _params, conn) do
    hub_identifier = hub_identifier_and_slug |> String.split("/") |> List.first()
    conn |> redirect_to_hub_identifier(hub_identifier)
  end

  def render_for_path("/discord", _params, conn), do: conn |> render_page("discord.html")
  def render_for_path("/discord/", _params, conn), do: conn |> render_page("discord.html")

  def render_for_path("/spoke", _params, conn), do: conn |> render_page("index.html", :spoke)
  def render_for_path("/spoke/" <> _path, _params, conn), do: conn |> render_page("index.html", :spoke)

  def render_for_path("/whats-new", _params, conn), do: conn |> render_page("whats-new.html")
  def render_for_path("/whats-new/", _params, conn), do: conn |> render_page("whats-new.html")

  def render_for_path("/hub.service.js", _params, conn), do: conn |> render_page("hub.service.js")
  def render_for_path("/manifest.webmanifest", _params, conn), do: conn |> render_page("manifest.webmanifest")

  def render_for_path("/admin", _params, conn), do: conn |> render_page("admin.html")

  def render_for_path("/" <> path, params, conn) do
    embed_token = params["embed_token"]

    [hub_sid | subresource] = path |> String.split("/")

    hub = Hub |> Repo.get_by(hub_sid: hub_sid)

    if embed_token && hub.embed_token != embed_token do
      conn |> send_resp(404, "Invalid embed token.")
    else
      conn =
        if embed_token do
          # Allow iframe embedding
          conn |> delete_resp_header("x-frame-options")
        else
          conn
        end

      render_hub_content(conn, hub, subresource |> Enum.at(0))
    end
  end

  def render_hub_content(conn, nil, _) do
    conn |> send_resp(404, "Invalid URL.")
  end

  def render_hub_content(conn, hub, "objects.gltf") do
    room_gltf = Ret.RoomObject.gltf_for_hub_id(hub.hub_id) |> Poison.encode!()

    conn
    |> put_resp_header("content-type", "model/gltf+json; charset=utf-8")
    |> send_resp(200, room_gltf)
  end

  def render_hub_content(conn, hub, _slug) do
    hub = hub |> Repo.preload(scene: [:screenshot_owned_file], scene_listing: [:screenshot_owned_file])

    hub_meta_tags =
      Phoenix.View.render_to_string(RetWeb.PageView, "hub-meta.html",
        hub: hub,
        scene: hub.scene,
        ret_meta: Ret.Meta.get_meta()
      )

    chunks =
      chunks_for_page("hub.html", :hubs)
      |> List.insert_at(1, hub_meta_tags)

    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_resp(200, chunks)
  end

  # Redirect to the specified hub identifier, which can be a sid or an entry code
  defp redirect_to_hub_identifier(conn, hub_identifier) do
    # Rate limit requests for redirects.
    :timer.sleep(500)

    hub = Repo.get_by(Hub, hub_sid: hub_identifier) || Hub.get_by_entry_code_string(hub_identifier)

    case hub do
      %Hub{} = hub -> conn |> redirect(to: "/#{hub.hub_sid}/#{hub.slug}")
      _ -> conn |> send_resp(404, "")
    end
  end

  defp render_page(conn, page, source \\ :hubs)

  defp render_page(conn, nil, _source) do
    conn |> send_resp(404, "")
  end

  defp render_page(conn, page, source) do
    chunks = page |> chunks_for_page(source)
    conn |> render_chunks(chunks, page |> content_type_for_page)
  end

  defp chunks_for_page(page, source) do
    res =
      if module_config(:skip_cache) do
        PageOriginWarmer.chunks_for_page(source, page)
      else
        Cachex.get(:page_chunks, {source, page})
      end

    with {:ok, chunks} <- res do
      chunks
    else
      _ -> nil
    end
  end

  defp content_type_for_page("hub.service.js"), do: "application/javascript; charset=utf-8"
  defp content_type_for_page("manifest.webmanifest"), do: "application/manifest+json"

  defp content_type_for_page(_) do
    "text/html; charset=utf-8"
  end

  defp render_chunks(conn, chunks, content_type) do
    conn
    |> put_resp_header("content-type", content_type)
    |> send_resp(200, chunks)
  end

  defp module_config(key) do
    Application.get_env(:ret, __MODULE__)[key]
  end
end
