{ system
  , compiler
  , flags
  , pkgs
  , hsPkgs
  , pkgconfPkgs
  , errorHandler
  , config
  , ... }:
  {
    flags = {};
    package = {
      specVersion = "2.2";
      identifier = { name = "plutus-tx"; version = "0.1.0.0"; };
      license = "Apache-2.0";
      copyright = "";
      maintainer = "michael.peyton-jones@iohk.io";
      author = "Michael Peyton Jones";
      homepage = "";
      url = "";
      synopsis = "Libraries for Plutus Tx and its prelude";
      description = "Libraries for Plutus Tx and its prelude";
      buildType = "Simple";
      isLocal = true;
      detailLevel = "FullDetails";
      licenseFiles = [ "LICENSE" "NOTICE" ];
      dataDir = ".";
      dataFiles = [];
      extraSrcFiles = [];
      extraTmpFiles = [];
      extraDocFiles = [ "README.md" ];
      };
    components = {
      "library" = {
        depends = [
          (hsPkgs."base" or (errorHandler.buildDepError "base"))
          (hsPkgs."bytestring" or (errorHandler.buildDepError "bytestring"))
          (hsPkgs."deepseq" or (errorHandler.buildDepError "deepseq"))
          (hsPkgs."template-haskell" or (errorHandler.buildDepError "template-haskell"))
          (hsPkgs."th-abstraction" or (errorHandler.buildDepError "th-abstraction"))
          (hsPkgs."prettyprinter" or (errorHandler.buildDepError "prettyprinter"))
          (hsPkgs."text" or (errorHandler.buildDepError "text"))
          (hsPkgs."mtl" or (errorHandler.buildDepError "mtl"))
          (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
          (hsPkgs."flat" or (errorHandler.buildDepError "flat"))
          (hsPkgs."plutus-core" or (errorHandler.buildDepError "plutus-core"))
          (hsPkgs."lens" or (errorHandler.buildDepError "lens"))
          (hsPkgs."ghc-prim" or (errorHandler.buildDepError "ghc-prim"))
          (hsPkgs."aeson" or (errorHandler.buildDepError "aeson"))
          (hsPkgs."hashable" or (errorHandler.buildDepError "hashable"))
          (hsPkgs."memory" or (errorHandler.buildDepError "memory"))
          (hsPkgs."serialise" or (errorHandler.buildDepError "serialise"))
          ];
        buildable = true;
        modules = [
          "PlutusTx/IsData/Instances"
          "PlutusTx/IsData/TH"
          "PlutusTx/Lift/THUtils"
          "PlutusTx/Lift/Instances"
          "PlutusTx"
          "PlutusTx/TH"
          "PlutusTx/Prelude"
          "PlutusTx/Evaluation"
          "PlutusTx/Applicative"
          "PlutusTx/Base"
          "PlutusTx/Bool"
          "PlutusTx/IsData"
          "PlutusTx/IsData/Class"
          "PlutusTx/ErrorCodes"
          "PlutusTx/Eq"
          "PlutusTx/Enum"
          "PlutusTx/Either"
          "PlutusTx/Foldable"
          "PlutusTx/Functor"
          "PlutusTx/Lattice"
          "PlutusTx/List"
          "PlutusTx/Ord"
          "PlutusTx/Integer"
          "PlutusTx/Maybe"
          "PlutusTx/Monoid"
          "PlutusTx/Numeric"
          "PlutusTx/Ratio"
          "PlutusTx/Semigroup"
          "PlutusTx/Sqrt"
          "PlutusTx/Traversable"
          "PlutusTx/AssocMap"
          "PlutusTx/Trace"
          "PlutusTx/These"
          "PlutusTx/Code"
          "PlutusTx/Lift"
          "PlutusTx/Lift/Class"
          "PlutusTx/Builtins"
          "PlutusTx/Builtins/Class"
          "PlutusTx/Builtins/Internal"
          "PlutusTx/Plugin/Utils"
          "PlutusTx/Utils"
          ];
        hsSourceDirs = [ "src" ];
        };
      tests = {
        "plutus-tx-test" = {
          depends = [
            (hsPkgs."base" or (errorHandler.buildDepError "base"))
            (hsPkgs."bytestring" or (errorHandler.buildDepError "bytestring"))
            (hsPkgs."plutus-core" or (errorHandler.buildDepError "plutus-core"))
            (hsPkgs."plutus-tx" or (errorHandler.buildDepError "plutus-tx"))
            (hsPkgs."hedgehog" or (errorHandler.buildDepError "hedgehog"))
            (hsPkgs."tasty" or (errorHandler.buildDepError "tasty"))
            (hsPkgs."tasty-hedgehog" or (errorHandler.buildDepError "tasty-hedgehog"))
            (hsPkgs."tasty-hunit" or (errorHandler.buildDepError "tasty-hunit"))
            (hsPkgs."serialise" or (errorHandler.buildDepError "serialise"))
            (hsPkgs."cborg" or (errorHandler.buildDepError "cborg"))
            ];
          build-tools = [
            (hsPkgs.buildPackages.doctest.components.exes.doctest or (pkgs.buildPackages.doctest or (errorHandler.buildToolDepError "doctest:doctest")))
            ];
          buildable = if compiler.isGhcjs && true || system.isWindows
            then false
            else true;
          hsSourceDirs = [ "test" ];
          mainPath = [ "Spec.hs" ];
          };
        };
      };
    } // {
    src = (pkgs.lib).mkDefault (pkgs.fetchgit {
      url = "15";
      rev = "minimal";
      sha256 = "";
      }) // {
      url = "15";
      rev = "minimal";
      sha256 = "";
      };
    postUnpack = "sourceRoot+=/plutus-tx; echo source root reset to \$sourceRoot";
    }