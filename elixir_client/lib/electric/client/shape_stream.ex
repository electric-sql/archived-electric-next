defmodule Electric.Client.ShapeStream do
  @moduledoc """
  GenStage producer for the Electric Shape API.

  Fetches messages using `Req` http client. Backs off in the event of failure.

  Maintains an offset position and internal queue of shape log messages.
  Broadcasts the log messages to all consumers in response to demand.
  """
  use GenStage
  use TypedStruct

  require Logger

  alias Req.Response, as: Resp

  alias Electric.Client.ShapeDefinition
  alias Electric.Client.Util

  alias __MODULE__.{
    Backoff,
    State
  }

  typedstruct module: Backoff do
    field :delay_ms, integer(), default: 100
    field :initial_delay_ms, integer(), default: 100
    field :max_delay_ms, integer(), default: 10_000
    field :multiplier, float(), default: 1.3
  end

  typedstruct module: State do
    field :base_url, String.t(), enforce: true
    field :instance_id, String.t(), enforce: true
    field :shape_definition, ShapeDefinition.t(), enforce: true

    field :backoff, Backoff.t(), default: %Backoff{}
    field :has_been_up_to_date, Boolean.t(), default: false
    field :is_up_to_date, Boolean.t(), default: false
    field :offset, Integer.t(), default: -1
    field :queue, Qex.t(), default: Qex.new()
    field :shape_id, String.t()

    field :demand, Integer.t(), default: 0
  end

  defimpl Collectable, for: State do
    def into(%State{offset: offset, queue: queue} = state) do
      collector_fun = fn
        acc, {:cont, item} ->
          accumulate(item, acc)

        acc, :done ->
          update(acc, state)

        _acc, :halt ->
          :ok
      end

      {{queue, offset, false}, collector_fun}
    end

    defp accumulate(item, acc) do
      Logger.debug("accumulate")

      item
      |> Jaxon.Stream.from_binary()
      |> Jaxon.Stream.query([:root])
      |> Stream.flat_map(fn messages -> messages end)
      |> Enum.reduce(acc, &accumulate_message/2)
    end

    defp accumulate_message(
           %{"offset" => new_offset} = message,
           {queue, current_offset, is_up_to_date}
         )
         when is_integer(new_offset) and new_offset > current_offset do
      Logger.debug("accumulate_message new_offset #{new_offset}")

      accumulate_message(message, {queue, new_offset, is_up_to_date})
    end

    defp accumulate_message(
           %{"headers" => %{"control" => "up-to-date"}} = message,
           {queue, offset, false}
         ) do
      Logger.debug("accumulate_message up_to_date")

      accumulate_message(message, {queue, offset, true})
    end

    defp accumulate_message(message, {queue, offset, is_up_to_date}) do
      Logger.debug("accumulate_message #{inspect(message)}")

      {Qex.push(queue, message), offset, is_up_to_date}
    end

    defp update({queue, offset, is_up_to_date}, state) do
      Logger.debug("update #{Enum.count(queue)} #{offset} #{is_up_to_date}")

      %{
        state
        | has_been_up_to_date: state.has_been_up_to_date || is_up_to_date,
          is_up_to_date: is_up_to_date,
          offset: offset,
          queue: queue
      }
    end
  end

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  def stream(opts) do
    {:ok, pid} = start_link(opts)

    {:ok, pid, GenStage.stream([pid])}
  end

  def stop(pid) do
    GenStage.stop(pid)
  end

  def init(opts) do
    state = struct!(State, [instance_id: Util.generate_id()] ++ opts)

    Process.send(self(), :fetch, [])

    {:producer, state, dispatcher: GenStage.BroadcastDispatcher}
  end

  def handle_info(:fetch, state) do
    state
    |> fetch()
    |> dispatch_events()
  end

  defp fetch(state) do
    state
    |> build_url()
    |> Req.get!(into: state)
    |> process(state)
  end

  defp build_url(%{
         base_url: base_url,
         shape_definition: %{table: table},
         is_up_to_date: is_up_to_date,
         offset: _offset,
         shape_id: shape_id
       }) do
    query =
      %{offset: -1}
      |> Util.map_put_if(:shape_id, shape_id, is_binary(shape_id))
      |> Util.map_put_if(:live, true, is_up_to_date)
      |> URI.encode_query()

    "#{base_url}/shape/#{table}?#{query}"
  end

  defp process(%Resp{status: status}, %{backoff: backoff} = state) when status > 299 do
    Logger.debug("Fetch failed #{status}")

    delay = backoff.delay_ms

    next_delay =
      (delay * backoff.multiplier)
      |> trunc()
      |> min(backoff.max_delay_ms)

    Process.send_after(self(), :fetch, delay)

    %{state | backoff: %{backoff | delay_ms: next_delay}}
  end

  defp process(%Resp{body: %{backoff: backoff, queue: queue} = state, headers: headers}, _state) do
    backoff = %{backoff | delay_ms: backoff.initial_delay_ms}
    shape_id = Enum.at(headers["x-electric-shape-id"], 0)

    Process.send(self(), :fetch, [])

    %{state | backoff: backoff, queue: queue, shape_id: shape_id}
  end

  def handle_demand(incoming_demand, %{demand: demand} = state) when incoming_demand > 0 do
    dispatch_events(%{state | demand: demand + incoming_demand})
  end

  defp dispatch_events(%{demand: 0} = state) do
    {:noreply, [], state}
  end

  defp dispatch_events(%{demand: demand, queue: queue} = state) do
    {events, num_taken, queue} = Util.take_from_queue(queue, demand)

    {:noreply, events, %{state | demand: demand - num_taken, queue: queue}}
  end
end
