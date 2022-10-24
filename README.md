# WithEx

Advanced replacement for `with` in Elixir. It has an interface similar to `Ecto.Multi`.

Advantages:

- **Simple is as simple does.** It turns complex `with` constructs into the ordinary pipes with similar to `Ecto.Multi` interface.
- **Allows to execute functions asynchronously.** Any function in a chain can be executed asynchronously using built-in task superviser (can be replaced with your own). No boilerplate is needed.
- **Allows to compose chains together and execute them as one unit.**

That's it. But do you need something else? [Let me know](https://github.com/undr/with_ex/issues) if you need.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `with_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:with_ex, "~> 0.1.0"}
  ]
end
```

## Examples

```elixir
defmodule NaiveImpl do
  def run(token, request) do
    with {_, :ok} <- {:validate, validate(token, request)},
         {_, {:ok, config}} <- {:config, get_config(token)},
         {_, {:ok, data1}} <- {:data1, get_data1(token, config.option1, config.add_option)},
         {_, {:ok, data2}} <- {:data2, get_data2(token, config.option2)},
         {_, :ok} <- {:before_event, emit(:before_event, token, request, data1, data2, config)},
         {_, {:ok, response}} <- {:response, execute(token, request, data1, data2, config)},
         {_, :ok} <- {:update_data1, update_data1(token, config.option1, config.add_option, response.data1)},
         {_, :ok} <- {:update_data2, update_data2(token, config.option2, response.data2)},
         {_, :ok} <- {:after_event, emit(:after_event, token, response)},
         {_, {:ok, result}} <- {:result, build_result(response)}
      Logger.info("success ...")
      {:ok, result}
    else
      {stage, {:error, reason}} ->
        Logger.info("failure ...")
        {:error, {stage, reason}}
    end
  end
end
```

```elixir
defmodule WithExImpl1 do
  alias WithEx.Chain

  def run(token, request) do
    Chain.new()
    |> Chain.run(:validate, __MODULE__, :validate, [token, request])
    |> Chain.run(:config, __MODULE__, :get_config, [token])
    |> Chain.run_async(:data1, __MODULE__, :get_data1, [token], timeout: 1000)
    |> Chain.run_async(:data2, __MODULE__, :get_data2, [token], timeout: 1000)
    |> Chain.run(:before_event, __MODULE__, :emit_before_event, [token, request])
    |> Chain.run(:response, __MODULE__, :execute_request, [token, request])
    |> Chain.run_async(:update_data1, __MODULE__, :update_data1, [token])
    |> Chain.run_async(:update_data2, __MODULE__, :update_data2, [token])
    |> Chain.run(:after_event, __MODULE__, :emit_after_event, [token])
    |> Chain.run(:result, __MODULE__, :build_result, [])
    |> Chain.finally(__MODULE__, :log_result, [token, request])
    |> Chain.exec()
  end

  def get_data1(token, %{config: config}) do
    ExternalAPI.get_data1(token, config.option1, config.add_option)
  end

  def log_result(token, req, {:ok, resp}, state) do
    Logger.info("success ...")
  end

  def log_result(token, req, {:error, {stage, reason}}, state) do
    Logger.info("failure ...")
  end

  # the rest of funcs...
end
```

or

```elixir
defmodule WithExImpl2 do
  alias WithEx.Chain

  def run(token, request) do
    Chain.new()
    |> Chain.run(:validate, validate_fun(token, request))
    |> Chain.run(:config, get_config_fun(token))
    |> Chain.run_async(:data1, get_data1_fun(token), timeout: 1000)
    |> Chain.run_async(:data2, get_data2_fun(token), timeout: 1000)
    |> Chain.run(:before_event, emit_before_event_fun(token, request))
    |> Chain.run(:response, execute_request_fun(token, request))
    |> Chain.run_async(:update_data1, update_data1_fun(token))
    |> Chain.run_async(:update_data2, update_data2_fun(token))
    |> Chain.run(:after_event, emit_after_event_fun(token))
    |> Chain.run(:result, build_result_fun())
    |> Chain.finally(log_result_fun(token, request))
    |> Chain.exec()
  end

  def valudate_fun(token, request) do
    fn(_) ->
      Validator.validate(%{token: token, request: request})
    end
  end

  def get_data1_fun(token) do
    fn(%{config: config}) ->
      ExternalAPI.get_data1(token, config.option1, config.add_option)
    end
  end

  def log_result_fun(token, req) do
    fn
      ({:ok, result}, effects) ->
        Logger.info("success ...")

      ({:error, {stage, reason}}, effects) ->
        Logger.info("failure ...")
    end
  end

  # the rest of funcs...
end
```
or

```elixir
defmodule WithExImpl3 do
  alias WithEx.Chain

  def run(token, request) do
    Chain.new()
    |> Chain.put(:token, token)
    |> Chain.put(:request, request)
    |> Chain.run(:validate, &validate/1)
    |> Chain.run(:config, &get_config/1)
    |> Chain.run_async(:data1, &get_data1/1, timeout: 1000)
    |> Chain.run_async(:data2, &get_data2/1, timeout: 1000)
    |> Chain.run(:before_event, &emit_before_event/1)
    |> Chain.run(:response, &execute_request/1)
    |> Chain.run_async(:update_data1, &update_data1/1)
    |> Chain.run_async(:update_data2, &update_data2/1)
    |> Chain.run(:after_event, &emit_after_event/1)
    |> Chain.run(:result, &build_result/1)
    |> Chain.finally(&log_result/2)
    |> Chain.exec()
  end

  def valudate(effects) do
    Validator.validate(effects)
  end

  def get_data1(%{token: token, config: config}) do
    ExternalAPI.get_data1(token, config.option1, config.add_option)
  end

  def log_result({:ok, resp}, effects) do
    Logger.info("success ...")
  end

  def log_result({:error, {stage, reason}}, effects) do
    Logger.info("failure ...")
  end

  # the rest of funcs...
end
```

```elixir
NaiveImpl.run("xxx", %{value: 100})
# => {:ok, result}
# => {:error, {:data2, :unreachable_service}}

WithExImpl1.run("xxx", %{value: 100})
# => {:ok, result, effects}
# => {:error, {:data2, :unreachable_service}, effects}

WithExImpl2.run("xxx", %{value: 100})
# => {:ok, result, effects}
# => {:error, {:data2, :unreachable_service}, effects}

WithExImpl3.run("xxx", %{value: 100})
# => {:ok, result, effects}
# => {:error, {:data2, :unreachable_service}, effects}
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/with_ex>.

