defmodule Teex.Pipeline.Download do
  @moduledoc false

  alias Teex.Types.Library
  alias Teex.Types.Error

  alias Teex.Net.ReleasesClient
  alias Teex.Net.TarClient

  @spec run(Teex.Types.Library.t()) ::
          {:error, Error.t()}
          | {:ok, Library.t()}
  def run(%Library{} = lib) do
    with {:ok, tar_data} <- do_tarball_download(lib),
         {:ok, checksum_string, deps} <- do_get_checksum(lib),
         lib <- insert_deps(lib, deps),
         :ok <- do_checksum_validation(checksum_string, tar_data) do
      {:ok, struct(lib, checksum: checksum_string, tarball: tar_data)}
    else
      e -> {:error, e}
    end
  end

  defp do_tarball_download(%Library{} = lib) do
    TarClient.download_tarball(lib.name, lib.version)
  end

  defp do_get_checksum(%Library{} = lib) do
    ReleasesClient.get_release_info(lib.name, lib.version)
    |> case do
      %{"checksum" => checksum_string, "requirements" => deps} -> {:ok, checksum_string, deps}
      e -> Error.build(type: :download, details: "Failed to download release info", data: e)
    end
  end

  defp insert_deps(lib, deps) when is_map(deps) do
    reqs =
      Enum.reduce(deps, [], fn {name, %{"requirement" => requirement}}, acc ->
        [{name, requirement} | acc]
      end)

    struct(lib, deps: reqs)
  end

  defp do_checksum_validation(valid_checksum, tar_data) do
    hash_test =
      :crypto.hash(:sha256, tar_data)
      |> Base.encode16()
      |> String.downcase()

    case hash_test do
      ^valid_checksum ->
        :ok

      _ ->
        Error.build(
          type: :checksum,
          details: "Checksum validation failed",
          data: [hex_checksum: valid_checksum, computed: hash_test]
        )
    end
  end
end
