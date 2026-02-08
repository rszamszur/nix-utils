{ ... }:

let
  inherit (builtins)
    attrNames
    filter
    hasAttr
    head
    isAttrs
    listToAttrs
    match
    readDir
    substring
    ;

  /**
    This function reads all visible contents under directory including .skip-tree and .skip-subtree markers.

    # Example

    ```nix
    readDirVisible ./.
    =>
    {
      bazel = "directory";
      "default.nix" = "regular";
      docs = "directory";
      nix = "directory";
      ops = "directory";
      "shell.nix" = "regular";
      tools = "directory";
    }
    ```

    # Type

    ```
    readDirVisible :: Path -> AttrSet
    ```

    # Arguments

    path
    : The path to a directory to read
  */
  readDirVisible =
    path:
    let
      children = readDir path;
      # skip hidden files, except for those that contain special instructions to readTree
      isVisible = f: f == ".skip-subtree" || f == ".skip-tree" || (substring 0 1 f) != ".";
      names = filter isVisible (attrNames children);
    in
    listToAttrs (
      map (name: {
        inherit name;
        value = children.${name};
      }) names
    );

  /**
    This function imports an Nix expression file and enforce puqu convention.

    # Example

    ```nix
    importFile ./default.nix {}
    =>
    { foo = "bar"; }
    ```

    # Type

    ```
    importFile :: Path -> AttrSet -> a
    ```

    # Arguments

    path
    : The path to a Nix expression to import

    args
    : The arguments to call imported file
  */
  importFile =
    path: args:
    let
      importedFile = import path;
      pathType = builtins.typeOf importedFile;
    in
    if pathType != "lambda" then
      throw "readTree: trying to import ${toString path}, but it’s a ${pathType}, you need to make it a function like { pq, pkgs, ... }"
    else
      importedFile args;

  /**
    This extracts the filename from a given string, removing the .nix extension

    # Example

    ```nix
    nixFileName "foobar.nix"
    =>
    "foobar"
    ```

    If no match is found, the function returns null.
    ```nix
    nixFileName "sources.json"
    =>
    null
    ```

    # Type

    ```
    nixFileName :: String -> String
    ```

    # Arguments

    file
    : The filename
  */
  nixFileName =
    file:
    let
      res = match "(.*)\\.nix" file;
    in
    if res == null then null else head res;

  /**
    This function is internal implementation of readTree, which handles things like the
    skipping of trees and subtrees. The higher-level `readTree` method assembles the final attribute
    set out of these results at the top-level, and the internal `children` implementation unwraps and processes nested trees.

    # Example

    This method returns an attribute sets with either of two shapes:

    A tree was read successfully
    ```nix
    readTreeImpl { initPath = ./.; rootDir = true; args = {inherit pkgs;};}
    =>
    { ok = ...; }
    ```

    A tree was skipped
    ```nix
    readTreeImpl { initPath = ./.; rootDir = true; args = {};}
    =>
    { skip = true; }
    ```

    # Type

    ```
    readTreeImpl :: Path -> Bool -> AttrSet -> AttrSet
    ```

    # Arguments

    initPath
    : The initial path to start reading the directory tree from.
    rootDir
    : A boolean indicating whether this is the root directory of the tree. If true, no default Nix file will be imported.
    args
    : An attribute set containing additional arguments that can be passed to importFile.
  */
  readTreeImpl =
    {
      initPath,
      rootDir,
      args,
    }:
    let
      dir = readDirVisible initPath;

      # Determine whether any part of this tree should be skipped.
      #
      # Adding a `.skip-subtree` file will still allow the import of
      # the current node's "default.nix" file, but stop recursion
      # there.
      #
      # Adding a `.skip-tree` file will completely ignore the folder
      # in which this file is located.
      skipTree = hasAttr ".skip-tree" dir;
      skipSubtree = skipTree || hasAttr ".skip-subtree" dir;

      joinChild = c: initPath + ("/" + c);

      self = if rootDir then { } else importFile initPath args;

      # Import subdirectories of the current one, unless any skip
      # instructions exist.
      filterDir = f: dir."${f}" == "directory";
      filteredChildren = map (c: {
        name = c;
        value = readTreeImpl {
          args = args;
          initPath = (joinChild c);
          rootDir = false;
        };
      }) (filter filterDir (attrNames dir));

      # Remove skipped children from the final set, and unwrap the
      # result set.
      children =
        if skipSubtree then
          [ ]
        else
          map (
            { name, value }:
            {
              inherit name;
              value = value.ok;
            }
          ) (filter (child: child.value ? ok) filteredChildren);

      # Import Nix files
      nixFiles = if skipSubtree then [ ] else filter (f: f != null) (map nixFileName (attrNames dir));
      nixChildren = map (
        c:
        let
          p = joinChild (c + ".nix");
          imported = importFile p args;
        in
        {
          name = c;
          value = imported;
        }
      ) nixFiles;

      nodeValue = if dir ? "default.nix" then self else { };

      allChildren = listToAttrs (if dir ? "default.nix" then children else nixChildren ++ children);
    in
    if skipTree then
      { skip = true; }
    else
      {
        ok = if isAttrs nodeValue then nodeValue // allChildren else nodeValue;
      };

  /**
    Top-level implementation of readTree itself.
  */
  readTree =
    args:
    let
      tree = readTreeImpl args;
    in
    if tree ? skip then
      throw "Top-level folder has a .skip-tree marker and could not be read by readTree!"
    else
      tree.ok;
in
{
  __functor =
    _:
    {
      path,
      args,
      rootDir ? true,
    }:
    readTree {
      inherit args rootDir;
      initPath = path;
    };

  /**
    This definition of fix is identical to <nixpkgs>.lib.fix, but is
    provided here for cases where readTree is used before nixpkgs can
    be imported.

    It is often required to create the args attribute set.
  */
  fix =
    f:
    let
      x = f x;
    in
    x;
}
