defmodule Porcelain.App do
  @moduledoc false

  use Application

  def start(_, _) do
    case Porcelain.Init.init() do
      :ok ->
        # dummy supervisor
        opts = [strategy: :one_for_one, name: Porcelain.Supervisor]
        Supervisor.start_link([], opts)
      other -> other
    end
  end
end
