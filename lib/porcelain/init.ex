defmodule Porcelain.Init do
  @moduledoc false

  require Logger

  alias Porcelain.Driver.Basic
  alias Porcelain.Driver.Goon

  def init() do
    driver = get_env(:driver)
    ok_pipe([
      fn -> init(driver) end,
      fn -> init_shell() end,
      fn -> :ok end,
    ])
  end

  # The user hasn't specified the required driver. We are free to choose the most appropriate one.
  def init(nil) do
    # We check if goon is available first because it is the preferred way to interact with
    # external processes
    case init_goon_driver() do
      {:ok, path} ->
        set_driver(Goon, path)

      {:error, error} ->
        case error do
          :goon_not_found ->
            if Application.get_env(:porcelain, :goon_warn_if_missing, true) do
              Logger.info ["[Porcelain]: ", error_string(error)]
              Logger.info "[Porcelain]: falling back to the basic driver."
              Logger.info "[Porcelain]: (set `config :porcelain, driver: Porcelain.Driver.Basic` "
                       <> "or `config :porcelain, goon_warn_if_missing: false` to disable this "
                       <> "warning)"
            end
          other ->
            Logger.warn ["[Porcelain]: ", error_string(other)]
            Logger.warn "[Porcelain]: falling back to the basic driver."
        end
        set_driver(Basic)
    end
  end

  # The user asks to use goon specifically. We will fail if it can't be initialized.
  def init(Goon) do
    case init_goon_driver() do
      {:ok, path}     -> set_driver(Goon, path)
      {:error, error} -> {:error, error_string(error)}
    end
  end

  def init(mod) when is_atom(mod), do: set_driver(mod)


  defp init_goon_driver() do
    if path = find_goon() do
      if Goon.check_goon_version(path) do
        {:ok, path}
      else
        {:error, {:goon_bad_version, path}}
      end
    else
      {:error, :goon_not_found}
    end
  end

  defp init_shell() do
    # Finding shell command logic from :os.cmd in OTP
    # https://github.com/erlang/otp/blob/8deb96fb1d017307e22d2ab88968b9ef9f1b71d0/lib/kernel/src/os.erl#L184
    case :os.type do
      {:unix, _} ->
        set_env(:shell_command, {'sh', ["-c"]})

      {:win32, osname} ->
        shell = case {System.get_env("COMSPEC"), osname} do
          {nil, :windows} -> 'command.com'
          {nil, _}        -> 'cmd'
          {cmd, _}        -> String.to_char_list(cmd)
        end
        set_env(:shell_command, {shell, ["/c"]})
    end
  end


  defp get_env(key) do
    Application.get_env(:porcelain, key)
  end

  # this function has to return :ok
  defp set_driver(mod, state \\ nil) do
    :ok = set_env(:driver_internal, mod)
    :ok = set_env(:driver_state, state)
    :ok
  end

  defp set_env(key, term) do
    Application.put_env(:porcelain, key, term)
  end

  defp find_goon() do
    cond do
      path=get_env(:goon_driver_path) ->
        path
      File.exists?("goon") ->
        Path.absname("goon")
      exe=:os.find_executable('goon') ->
        List.to_string(exe)
      true -> false
    end
  end

  defp ok_pipe([h|t]) do
    case h.() do
      {:error, _}=error -> error
      :ok -> ok_pipe(t)
    end
  end

  defp ok_pipe([]), do: :ok

  defp error_string({:goon_bad_version, path}) do
    "goon executable at #{path} does not support protocol version #{Goon.proto_version}"
  end

  defp error_string(:goon_not_found) do
    "goon executable not found"
  end
end
