# SwarmBrain (BRAIN)

`src/SwarmBrain.sol:SwarmBrain` is a standard ERC-20 with a fixed supply.

| Parameter | Value |
| --- | --- |
| Name | SwarmBrain |
| Symbol | BRAIN |
| Decimals | 18 |
| Whole-token supply | 1,000,000,000 |
| Base-unit supply | 1000000000000000000000000000 (10^27) |
| Constructor arguments | None |
| Initial recipient | Constructor caller (`msg.sender`) |

The constructor mints the entire supply once and emits `Transfer(address(0), deployer, supply)`.
Transfers deliver the exact amount, with no tax, fee, rebasing, or transfer restrictions
beyond standard ERC-20 validation. There is no external mint, burn, owner, pause,
blacklist, seizure, upgrade, or initialization function. Deploy directly, not behind a proxy.

## Build and check

With Foundry and Solidity 0.8.26 installed, run from this repository's root:

```sh
forge build
forge test
forge fmt --check
```

Dependencies are vendored (see `DEPENDENCIES.md`). Configuration pins Solidity 0.8.26,
the Cancun EVM target, optimizer settings, and `bytecode_hash = "none"`. The deployment
chain must support Cancun. Tests require no environment variables, RPC, filesystem
permissions, or FFI. Unit tests cover metadata, constructor allocation and event,
transfers, approvals, delegated transfers, failures and rollback, and launch-style
distribution. Fuzz and stateful invariant tests check balance conservation and fixed supply.

## Deployment and operations

The network deployer should use the compiled `SwarmBrain` creation bytecode with **no
constructor arguments and no native currency**. When a factory creates the token, the
factory receives all tokens; when an EOA deploys it directly, that EOA receives them.
There is no recipient override or post-deployment setup. This matches the requested
allocation to the deployer and the custom-token factory launch flow.

The launch system, rather than this token, handles distribution, liquidity, and its
launch manifest. No tokens are allocated elsewhere inside the constructor. This project
does not deploy contracts, broadcast transactions, open a pool, or generate a manifest.

Before launch, the deployer is responsible for verifying the chain, constructor caller,
bytecode, supply, and intended distribution. After deployment, verify the source on
the explorer and confirm the full supply belongs to the deploying caller. There are no
administrative settings, maintenance calls, or privileged keys to configure. Holders
control their balances and spender approvals. The factory must protect the supply it
receives until distribution; receipt of the supply confers no token administration rights.

## Assumptions and security review

The brief specifies standard ERC-20 behavior; permit signatures, governance, staking,
vesting, transfer callbacks, and application contracts are outside this implementation.
Zero-value transfers are valid and emit events. Zero-address transfers and approvals
revert. Approvals replace the previous allowance; finite allowances decrease on spending,
while `type(uint256).max` is treated as unlimited by OpenZeppelin. Spender access persists
until revoked or exhausted, so holders should approve only what they intend to spend.
Changing an existing allowance has the standard ERC-20 transaction-ordering risk; revoke
it first and confirm that transaction before assigning a replacement where necessary.

Tokens sent to the token contract or another address without a withdrawal mechanism
cannot be recovered by an administrator. Native currency sent forcibly is likewise
unrecoverable; ordinary native-currency transfers revert.

Review against the supplied security reference found no external calls in token operations,
no oracle or randomness dependency, no privileged balance manipulation, and no proxy or
linked external library. Only the constructor calls the internal mint operation.
Local validation uses Foundry unit, fuzz, and invariant tests and a runtime opcode check.
Slither and Mythril were not run. These checks do not constitute an independent security
audit; independent adversarial review remains a release responsibility.

Local validation passed with Solidity 0.8.26: `forge build`, `forge test` (27 tests,
including three fuzz tests with 1,000 cases each and 256 invariant runs at depth 64),
and `forge fmt --check`. A clean copy containing only `src/`, `test/`, `lib/`, and
`foundry.toml` also passed `forge build --offline`, `forge test --offline --threads 4`,
and `forge fmt --check`, without the supplied input files or previous build artifacts.
The independent launch harness is run by the verifier; the local launch-style test
checks exact token movements without deploying an actual Uniswap pool.
