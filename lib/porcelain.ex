defmodule Porcelain do
  defmodule Result do
    @doc """
    A struct containing the result of running a program after it has
    terminated.
    """
    defstruct [:status, :out, :err]
  end


  @doc """
  Execute a program synchronously.

  Porcelain will look for the program in PATH and launch it directly, passing
  the `args` list as command-line arguments to it.

  Feeds all input into the program (synchronously or concurrently with reading
  output; see `:async_in` option below) and waits for it to terminate. Returns
  a `Porcelain.Result` struct containing program's output and exit status code.

  When no options are passed, the following defaults will be used:

      [in: "", async_in: true, out: :string, err: nil]

  This will run the program with no input and will capture its standard output.

  Available options:

    * `:in` – specify the way input will be passed to the program.

      Possible values:

      - `<iodata>` – the data is fed into stdin as the sole input for the
        program

      - `<stream>` – interprets `<stream>` as a stream of iodata to be fed into
        the program

      - `{:path, <string>}` – path to a file to be fed into stdin

      - `{:file, <file>}` – `<file>` is a file pid obtained from e.g.
        `File.open`; the file will be read from the current position until EOF

    * `:async_in` – can be `true` or `false` (default). When enabled, an
      additional process will be spawned to feed input to the program
      concurrently with receiving output.

    * `:out` – specify the way output will be passed back to Elixir.

      Possible values:

      - `nil` – discard the output

      - `:string` (default) – the whole output will be accumulated in memory
        and returned as one string to the caller

      - `:iodata` – the whole output will be accumulated in memory and returned
        as iodata to the caller

      - `{:path, <string>}` – the file at path will be created (or truncated)
        and the output will be written to it

      - `{:append, <string>}` – the output will be appended to the the file at
        path (it will be created first if needed)

      - `{:file, <file>}` – `<file>` is a file pid obtained from e.g.
        `File.open`; the file will be written to starting at the current
        position

    * `:err` – specify the way stderr will be passed back to Elixir.

      Possible values are the same as for `:out`. In addition, it accepts the
      atom `:out` which denotes redirecting stderr to stdout.

      **Caveat**: when using `Porcelain.Driver.Simple`, the only supported
      values are `nil` (stderr will be printed to the terminal) and `:out`.

    * `:env` – set additional environment variables for the program. The value
      should be an enumerable with elements of the shape `{<key>, <val>}` where
      `<key>` is an atom or a binary and `<val>` is a binary or `false`
      (meaning removing the corresponding variable from the environment).
      Basically, it accepts any kind of dict, including keyword lists.

  """
  # TODO: check if ports workk with iodata arguments and names
  @spec exec(binary, [binary])            :: Porcelain.Result.t
  @spec exec(binary, [binary], Keyword.t) :: Porcelain.Result.t

  def exec(prog, args, options \\ [])
        when is_binary(prog) and is_list(args) and is_list(options)
  do
    catch_wrapper fn ->
      driver().exec(prog, args, compile_exec_options(options))
    end
  end


  @doc """
  Execute a shell invocation synchronously.

  This function will launch a system shell and pass the invocation to it. This
  allows using shell features like haining multiple programs with pipes. The
  downside is that those advanced features may be unavailable on some
  platforms.

  It is similar to the `exec/3` function in all other respects.
  """
  @spec shell(binary)            :: Porcelain.Result.t
  @spec shell(binary, Keyword.t) :: Porcelain.Result.t

  def shell(cmd, options \\ []) when is_binary(cmd) and is_list(options) do
    catch_wrapper fn ->
      driver().exec_shell(cmd, compile_exec_options(options))
    end
  end


  @doc """
  Spawn an external process and return a `Porcelain.Process` struct to be able
  to communicate with it.

  You have to explicitly close the process after reading its output and when it
  is no longer needed.

  Use the `Porcelain.Process.await/2` function to wait for the process to
  terminate.

  Supports all options defined for `exec/3` plus some additional ones:

    * `in: :receive` – input is expected to be sent to the process in chunks
      using the `send/2` function.

    * `out: :stream` – the `:out` field of the returned `Process` struct will
      contain a stream of iodata.

      Note that the underlying port implementation is message based. This means
      that the external program will be able to send all of its output to an
      Elixir process and terminate. The data will be kept in the Elixir
      process's message box until the stream is consumed.

    * `err: :stream` – same as `:out`, but will return stderr as a stream.

    * `:result` – specify how the result of the external program should be
    returned after it has terminated.

      Possible values:

      * `:keep` (default) – the result will be kept in memory until requested
        by calling `Porcelain.Process.await/2`.

      * `:discard` – discards the result and automatically closes the port
        after program termination. Useful in combination with `out: :stream`
        and `err: :stream`.

      * `{:send, <pid>}` – the result will be sent to `<pid>`. The
        `Porcelain.Process` struct returned from `spawn/3` or `spawn_shell/2`
        will have it's result field set to `{:send, <ref>}`. The actual message
        with `Porcelain.Result` struct will have this shape:

              {<ref>, %Porcelain.Result{}}

  """
  @spec spawn(binary, [binary])            :: Porcelain.Process.t
  @spec spawn(binary, [binary], Keyword.t) :: Porcelain.Process.t

  def spawn(prog, args, options \\ [])
    when is_binary(prog) and is_list(args) and is_list(options)
  do
    catch_wrapper fn ->
      driver().spawn(prog, args, compile_spawn_options(options))
    end
  end


  @doc """
  Spawn a system shell and execute the command in it.

  Works similar to `spawn/3`.
  """
  @spec spawn_shell(binary)            :: Porcelain.Process.t
  @spec spawn_shell(binary, Keyword.t) :: Porcelain.Process.t

  def spawn_shell(cmd, options \\ [])
        when is_binary(cmd) and is_list(options)
  do
    catch_wrapper fn ->
      driver().spawn_shell(cmd, compile_spawn_options(options))
    end
  end

  ###

  defp catch_wrapper(fun) do
    try do
      fun.()
    catch
      :throw, thing -> {:error, thing}
    end
  end


  defp compile_exec_options(options) do
    {good, bad} = Enum.reduce(options, {[], []}, fn {name, val}, {good, bad} ->
      compiled = case name do
        :in  -> compile_input_opt(val)
        :out -> compile_output_opt(val)
        :err -> compile_error_opt(val)
        :env -> compile_env_opt(val)
        :async_in ->
          if val in [true, false] do
            {:ok, val}
          end
        _ -> nil
      end
      case compiled do
        nil        -> {good, bad ++ [{name, val}]}
        {:ok, opt} -> {good ++ [{name, opt}], bad}
      end
    end)
    if not Keyword.has_key?(options, :out) do
      good = Keyword.put(good, :out, {:string, ""})
    end
    {good, bad}
  end

  defp compile_spawn_options(options) do
    {good, bad} = compile_exec_options(options)
    {good, bad} = Enum.reduce(bad, {good, []}, fn opt, {good, bad} ->
      compiled = case opt do
        {:in, :receive}     -> :ok
        {:out, :stream}     -> :ok
        {:err, :stream}     -> :ok
        {:result, :keep}    -> :ok
        {:result, :discard} -> :ok
        {:result, {:send, pid}} when is_pid(pid) -> :ok
        _ -> nil
      end
      case compiled do
        :ok -> {good ++ [opt], bad}
        nil -> {good, bad ++ [opt]}
      end
    end)
    if not Keyword.has_key?(good, :result) do
      good = Keyword.put(good, :result, :keep)
    end
    {good, bad}
  end

  defp compile_input_opt(opt) do
    result = case opt do
      nil                                              -> nil
      #:pid                                             -> :pid
      {:file, fid}=x when is_pid(fid)                  -> x
      {:path, path}=x when is_binary(path)             -> x
      iodata when is_binary(iodata) or is_list(iodata) -> iodata
      other ->
        if Enumerable.impl_for(other) != nil do
          other
        else
          :badval
        end
    end
    if result != :badval, do: {:ok, result}
  end

  defp compile_output_opt(opt) do
    compile_out_opt(opt, nil)
  end

  defp compile_error_opt(opt) do
    compile_out_opt(opt, :out)
  end

  defp compile_out_opt(opt, typ) do
    result = case opt do
      ^typ                                   -> typ
      nil                                    -> nil
      :string                                -> {:string, ""}
      :iodata                                -> {:iodata, ""}
      {:file, fid}=x when is_pid(fid)        -> x
      {:path, path}=x when is_binary(path)   -> x
      {:append, path}=x when is_binary(path) -> x
      #{pid, ref} when is_pid(pid) -> { pid, ref }
      _ -> :badval
    end
    if result != :badval, do: {:ok, result}
  end

  defp compile_env_opt(val) do
    {vars, ok?} = Enum.map_reduce(val, true, fn
      {name, val}, ok? when (is_binary(name) or is_atom(name))
                        and (is_binary(val) or val == false) ->
        {{convert_env_name(name), convert_env_val(val)}, ok?}
      other, _ -> {other, false}
    end)
    if ok?, do: {:ok, vars}
  end

  defp convert_env_name(name) when is_binary(name),
    do: String.to_char_list(name)

  defp convert_env_name(name) when is_atom(name),
    do: Atom.to_char_list(name)

  defp convert_env_val(false), do: false

  defp convert_env_val(bin), do: String.to_char_list(bin)


  # dynamic selection of the execution driver which does all the hard work
  defp driver() do
    case :application.get_env(:porcelain, :driver) do
      :undefined -> Porcelain.Driver.Simple
      other -> other
    end
  end


    #{port, input, output, error} = init_port_connection(cmd, args, options)
    #proc = %Process{in: input, out: output, err: error}
    #parent = self
    #pid = Kernel.spawn(fn -> do_loop(port, proc, parent) end)
    ##Port.connect port, pid
    #{pid, port}

  #@doc """
  #Takes a shell invocation and produces a tuple `{ cmd, args }` suitable for
  #use in `exec()` and `spawn()` functions. The format of the invocation should
  #conform to POSIX shell specification.

  #TODO: define behaviour of env variables, pipes, redirects

  ### Examples

      #iex> Porcelain.shplit(~s(echo "Multiple arguments" in one line))
      #{"echo", ["Multiple arguments", "in", "one", "line"]}

  #"""
  #def shplit(invocation) when is_binary(invocation) do
    #case String.split(invocation, " ", global: false) do
      #[cmd, rest] ->
        #{ cmd, split(rest) }
      #[cmd] ->
        #{ cmd, [] }
    #end
  #end

  ## This splits the list of arguments with the command name already stripped
  #defp split(args) when is_binary(args) do
    #String.split args, " "
  #end


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

  #defp port_options(options, cmd, args) do
    #flags = get_flags(options)
    ##[{:args, List.flatten([["run", "main.go"], flags, ["--"], [cmd | args]])},
    #all_args = List.flatten([flags, ["--"], [cmd | args]])
    #[{:args, all_args}, :binary, {:packet, 2}, :exit_status, :use_stdio, :hide]
  #end

  #defp get_flags(options) do
    #[
      #["-proto", "2l"],

      #case options[:out] do
        #nil  -> ["-out", ""]
        #:err -> ["-out", "err"]
        #_    -> []
      #end,

      #case options[:err] do
        #nil  -> ["-err", ""]
        #:out -> ["-err", "out"]
        #_    -> []
      #end
    #]
  #end

  #defp open_port(opts) do
    #goon = if File.exists?("goon") do
      #'goon'
    #else
      #:os.find_executable 'goon'
    #end
    #Port.open { :spawn_executable, goon }, opts
  #end

  ## Processes port options opens a port. Used in both call() and spawn()
  #defp init_port_connection(cmd, args, options) do
    #port = open_port(port_options(options, cmd, args))

    #input  = process_input_opts(options[:in])
    #output = process_output_opts(options[:out])
    #error  = process_error_opts(options[:err])

    #{ port, input, output, error }
  #end
end
