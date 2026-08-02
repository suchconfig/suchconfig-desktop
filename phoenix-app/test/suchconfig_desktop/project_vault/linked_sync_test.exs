defmodule SuchConfigDesktop.ProjectVault.LinkedSyncTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktop.EnvManager.ProjectFolder
  alias SuchConfigDesktop.ProjectVault.LinkedSync

  test "absolute_path rejects path escape" do
    tmp = System.tmp_dir!()
    root = Path.join(tmp, "linked_root")
    File.mkdir_p!(root)
    outside = Path.join(tmp, "outside.txt")
    File.write!(outside, "x")

    folder = %ProjectFolder{linked_project_path: root}

    assert {:error, :path_escape} =
             LinkedSync.absolute_path(folder, "../outside.txt")
  end

  test "absolute_path joins under root" do
    tmp = System.tmp_dir!()
    root = Path.join(tmp, "linked_root2")
    File.mkdir_p!(root)
    file = Path.join(root, ".env")
    File.write!(file, "A=1\n")

    folder = %ProjectFolder{linked_project_path: root}
    assert {:ok, ^file} = LinkedSync.absolute_path(folder, ".env")
  end
end
