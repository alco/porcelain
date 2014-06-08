defmodule Porcelain.UsageError do
  @moduledoc """
  This exception is meant to indicate programmer errors (misuses of the library
  API) that have to be fixed prior to release.
  """

  defexception [:message]
end
