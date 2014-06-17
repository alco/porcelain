defmodule Porcelain.Driver.Common do
  @moduledoc false

  use Behaviour

  defcallback exec(prog :: binary, args :: [binary], opts :: Keyword.t)
  defcallback exec_shell(prog :: binary, opts :: Keyword.t)
  defcallback spawn(prog :: binary, args :: [binary], opts :: Keyword.t)
  defcallback spawn_shell(prog :: binary, opts :: Keyword.t)


  def find_goon(shell_flag \\ :noshell)

  def find_goon(:noshell) do
    if File.exists?("goon") do
      'goon'
    else
      :os.find_executable('goon')
    end
  end

  def find_goon(:shell) do
    if File.exists?("goon") do
      "./goon"
    else
      :os.find_executable('goon')
    end
  end


  def compile_options({opts, []}) do
    opts
  end

  def compile_options({_opts, extra_opts}) do
    msg = "Invalid options: #{inspect extra_opts}"
    raise Porcelain.UsageError, message: msg
  end

  @common_options [:binary, :stream, :exit_status, :use_stdio, :hide]
  def port_options(opts) do
    ret = @common_options
    if dir=opts[:dir], do: ret = [{:cd, dir}|ret]
    if env=opts[:env], do: ret = [{:env, env}|ret]
    case {opts[:out], opts[:err], opts[:in]} do
      {nil, nil, nil} -> [:nouse_stdio|ret]
      {nil, nil, _}   -> [:in|ret]
      _               -> ret

      # seems :out doesn't work with :stderr_to_stdout
      # it is only used in the Goon driver
      #{_, _, nil}     -> [:out|ret]
    end
  end
end
