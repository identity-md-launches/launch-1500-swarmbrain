# Vendored dependencies

All required Solidity sources are ordinary files under `lib/`; installation, submodules,
and network access are unnecessary to build or test this project.

- OpenZeppelin Contracts **v5.1.0**, MIT: https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.1.0
  Only `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`,
  `draft-IERC6093.sol`, and the upstream license are included. These sources are unmodified.
- forge-std **v1.9.4**, Apache-2.0 OR MIT: https://github.com/foundry-rs/forge-std/tree/v1.9.4
  Upstream `src/` and both licenses are included unmodified, for testing only.

Archives were obtained from GitHub's codeload endpoint for the above version tags.
Every vendored file was compared byte-for-byte with its source archive.

Archive SHA-256 checksums:

```text
OpenZeppelin v5.1.0: 8a3b08cfc756437ba3343901565b18182adb42ec1e621960240a19da5d738686
forge-std v1.9.4:    9bf191808ba79584a69ee4f288bfb9f217d1187c43d46f59780d86cab9196a15
```
