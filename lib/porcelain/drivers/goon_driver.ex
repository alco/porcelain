defmodule Porcelain.Driver.Goon do
  @moduledoc """
  Porcelain driver that offers additional features over the basic one.

  Users are not supposed to call functions in this module directly. Use
  functions in `Porcelain` instead.

  This driver will be used by default if it can locate the external program
  named `goon` in the executable path. If `goon` is not found, Porcelain will
  fall back to the basic driver.

  The additional functionality provided by this driver is as follows:

    * ability to signal EOF to the external program
    * (to be implemented) send an OS signal to the program
    * (to be implemented) more efficient piping of multiple programs

  """

  @behaviour Porcelain.Driver.Common

  alias Porcelain.Driver.Common


  @doc false
  def exec(prog, args, opts) do
    do_exec(prog, args, opts, :noshell)
  end

  @doc false
  def exec_shell(prog, opts) do
    do_exec(prog, nil, opts, :shell)
  end


  @doc false
  def spawn(prog, args, opts) do
    do_spawn(prog, args, opts, :noshell)
  end

  @doc false
  def spawn_shell(prog, opts) do
    do_spawn(prog, nil, opts, :shell)
  end

  ###

  defp do_exec(prog, args, opts, shell_flag) do
    opts = Common.compile_options(opts)
    exe = find_executable(prog, shell_flag)
    port = Port.open(exe, port_options(shell_flag, prog, args, opts))
    communicate(port, opts[:in], opts[:out], opts[:err],
        async_input: opts[:async_in])
  end

  defp do_spawn(prog, args, opts, shell_flag) do
    opts = Common.compile_options(opts)
    exe = find_executable(prog, shell_flag)

    out_opt = opts[:out]
    out_ret = case out_opt do
      :stream ->
        {:ok, server} = StreamServer.start()
        out_opt = {:stream, server}
        Stream.unfold(server, &read_stream/1)

      {atom, ""} when atom in [:string, :iodata] ->
        atom

      _ -> out_opt
    end

    pid = spawn(fn ->
      port = Port.open(exe, port_options(shell_flag, prog, args, opts))
      communicate(port, opts[:in], out_opt, opts[:err],
          async_input: true, result: opts[:result])
    end)

    %Porcelain.Process{
      pid: pid,
      out: out_ret,
      err: opts[:err],
    }
  end


  @goon_executable 'goon'
  @proto_version "0.0"

  @doc false
  defp find_executable(prog, :noshell) do
    if :os.find_executable(:erlang.binary_to_list(prog)) do
      {:spawn_executable, @goon_executable}
    else
      throw "Command not found: #{prog}"
    end
  end

  defp find_executable(prog, :shell) do
    {:spawn, "#{@goon_executable} -proto #{@proto_version} -- #{prog}"}
  end


  defp port_options(:noshell, prog, args, opts) do
    args = ["-proto", @proto_version, "--", prog] ++ args
    [{:args, args} | common_port_options(opts)]
  end

  defp port_options(:shell, _, _, opts) do
    common_port_options(opts)
  end

  defp common_port_options(opts) do
    ret = Common.port_options(opts)
    case {opts[:out], opts[:err], opts[:in]} do
      {nil, nil, nil} -> ret
      {_, _, nil}     -> [:out|ret]
      _               -> ret
    end
  end

  defp communicate(port, input, output, error, opts) do
    input_fun = fn -> send_input(port, input) end
    if opts[:async_input] do
      spawn(input_fun)
    else
      input_fun.()
    end
    collect_output(port, output, error, opts[:result])
  end

  defp send_input(port, input) do
    case input do
      iodata when is_binary(iodata) or is_list(iodata) ->
        Port.command(port, input)

      {:file, fid} ->
        pipe_file(fid, port)

      {:path, path} ->
        File.open(path, [:read], fn(fid) ->
          pipe_file(fid, port)
        end)

      null when null in [nil, :receive] ->
        nil

      other -> stream_to_port(other, port)
    end
    ## Send EOF to indicate the end of input or no input
    #Port.command(port, "")
  end

  defp read_stream(server) do
    case StreamServer.get_data(server) do
      nil  -> nil
      data -> {data, server}
    end
  end

  # we read files in blocks to avoid excessive memory usage
  @file_block_size 1024*1024

  defp pipe_file(fid, port) do
    Stream.repeatedly(fn -> IO.read(fid, @file_block_size) end)
    |> Stream.take_while(fn
      :eof        -> false
      {:error, _} -> false
      _           -> true
    end)
    |> stream_to_port(port)
  end

  defp stream_to_port(enum, port) do
    # set up a try block, because the port may close before consuming all input
    try do
      Enum.each(enum, fn
        iodata when is_list(iodata) or is_binary(iodata) ->
          # the sleep is needed to work around the problem of port hanging
          :timer.sleep(1)
          Port.command(port, iodata, [:nosuspend])
        byte ->
          :timer.sleep(1)
          Port.command(port, [byte])
      end)
    catch
      :error, :badarg -> nil
    end
  end

  defp collect_output(port, output, error, result_opt) do
    receive do
      { ^port, {:data, data} } ->
        output = process_port_output(output, data)
        collect_output(port, output, error, result_opt)

      { ^port, {:exit_status, status} } ->
        result = finalize_result(status, output, error)
        send_result(output, result_opt, result)
        || case result_opt do
          nil      -> result
          :discard -> nil
          :keep    -> wait_for_command(result)
        end

      {:input, data} ->
        Port.command(port, data)
        collect_output(port, output, error, result_opt)

      {:stop, from, ref} ->
        Port.close(port)
        result = finalize_result(nil, output, error)
        send_result(output, result_opt, result)
        send(from, {ref, :stopped})
    end
  end

  defp finalize_result(status, out, err) do
    %Porcelain.Result{status: status, out: flatten(out), err: flatten(err)}
  end

  defp send_result({:send, pid}, opt, result) do
    if opt == :discard, do: result = nil
    send(pid, {self(), :result, result})
    true
  end

  defp send_result(_, _, _), do: false

  defp wait_for_command(result) do
    receive do
      {:stop, from, ref} ->
        send(from, {ref, :stopped})
      {:get_result, from, ref} ->
        send(from, {ref, result})
    end
  end


  defp process_port_output(nil, _) do
    nil
  end

  defp process_port_output({typ, data}, new_data)
    when typ in [:string, :iodata]
  do
    {typ, [data, new_data]}
  end

  defp process_port_output({:file, fid}=x, data) do
    :ok = IO.write(fid, data)
    x
  end

  defp process_port_output({:path, path}, data) do
    {:ok, fid} = File.open(path, [:write])
    process_port_output({:path, path, fid}, data)
  end

  defp process_port_output({:append, path}, data) do
    {:ok, fid} = File.open(path, [:append])
    process_port_output({:path, path, fid}, data)
  end

  defp process_port_output({:path, _, fid}=x, data) do
    :ok = IO.write(fid, data)
    x
  end

  defp process_port_output({:stream, server}=x, data) do
    StreamServer.put_data(server, data)
    x
  end

  defp process_port_output({:send, pid}=x, data) do
    send(pid, {self(), :data, data})
    x
  end

  #defp process_port_output({ pid, ref }=a, in_data, type) when is_pid(pid) do
    #Kernel.send(pid, { ref, type, in_data })
    #a
  #end

  defp flatten(thing) do
    case thing do
      {:string, data}    -> IO.iodata_to_binary(data)
      {:iodata, data}    -> data
      {:path, path, fid} -> File.close(fid); {:path, path}
      {:stream, server}  -> StreamServer.finish(server)
      other              -> other
    end
  end
  ## Runs in a recursive loop until the process exits
  #defp collect_output(port, output, error) do
    ##IO.puts "Collecting output"
    #receive do
      #{ ^port, {:data, <<?o, data :: binary>>} } ->
        ##IO.puts "Did receive out"
        #output = process_port_output(output, data, :stdout)
        #collect_output(port, output, error)

      #{ ^port, {:data, <<?e, data :: binary>>} } ->
        ##IO.puts "Did receive err"
        #error = process_port_output(error, data, :stderr)
        #collect_output(port, output, error)

      #{ ^port, {:exit_status, status} } ->
        #{ status, flatten(output), flatten(error) }

      ##{ ^port, :eof } ->
        ##collect_output(port, output, out_data, err_data, true, did_see_exit, status)
    #end
  #end


  #defp do_loop(port, proc=%Process{in: in_opt}, parent) do
    #Port.connect port, self
    #if in_opt != :pid do
      #send_input(port, in_opt)
    #end
    #exchange_data(port, proc, parent)
  #end

  #defp exchange_data(port, proc=%Process{in: input, out: output, err: error}, parent) do
    #receive do
      #{ ^port, {:data, <<?o, data :: binary>>} } ->
        ##IO.puts "Did receive out"
        #output = process_port_output(output, data, :stdout)
        #exchange_data(port, %{proc|out: output}, parent)

      #{ ^port, {:data, <<?e, data :: binary>>} } ->
        ##IO.puts "Did receive err"
        #error = process_port_output(error, data, :stderr)
        #exchange_data(port, %{proc|err: error}, parent)

      #{ ^port, {:exit_status, status} } ->
        #Kernel.send(parent, {self, %Process{status: status,
                                            #in: input,
                                            #out: flatten(output),
                                            #err: flatten(error)}})

      #{ :data, :eof } ->
        #Port.command(port, "")
        #exchange_data(port, proc, parent)

      #{ :data, data } when is_binary(data) ->
        #Port.command(port, data)
        #exchange_data(port, proc, parent)
    #end
  #end
end
