defmodule Electric.Plug.DeleteShapePlug do
  require Logger
  alias Electric.Shapes
  alias Electric.Electric.Plug.ServeShapePlug.Params
  use Plug.Builder

  plug :fetch_query_params
  plug :put_resp_content_type, "application/json"
  
  plug :allow_shape_deletion
  plug :validate_query_params
  
  plug :truncate_shape

  defp allow_shape_deletion(%Plug.Conn{} = conn, _) do
    if Application.get_env(:electric, Electric)[:allow_shape_deletion] do
      conn
    else
      conn
      |> send_resp(404, Jason.encode_to_iodata!(%{status: "Not found"}))
      |> halt()
    end
  end

  defp validate_query_params(%Plug.Conn{} = conn, _) do
    params =
      Map.merge(conn.query_params, conn.path_params)
      |> Map.take("shape_definition")
      |> Map.put("offset", -1)

    case Params.validate(all_params, []) do
      {:ok, params} ->
        %{conn | assigns: Map.merge(conn.assigns, params)}

      {:error, error_map} ->
        conn
        |> send_resp(400, Jason.encode_to_iodata!(error_map))
        |> halt()
    end
  end

  defp truncate_shape(%Plug.Conn{} = conn, _) do
    with {shape_id, _} <- Shapes.get_or_create_shape_id(conn.assigns.shape_definition),
         :ok <- Electric.InMemShapeCache.handle_truncate(shape_id) do
      send_resp(conn, 204, "")
    end
  end
end
