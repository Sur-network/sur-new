# Limitations (Besu round 1, v2.5)

- One host, Docker bridge networking, no real network latency or hostile conditions. Short runs (about 1,100 blocks on Net-A).
- Besu cannot advance time. Every timer of 72 h or longer is NOT-RUN, except where the Net-T overlay shortened it (D-3).
- Bonsai keeps about 512 blocks of state, so historical balance checks were done inside that window; attribution and fees come from blocks and receipts.
- The BG-10 JSON is post hoc: the live negatives and the pot-to-DAO delta exist only in the interactive stdout.
- BG-12b measured n=1 and n=6 only and extrapolates. The gas Besu gives its own contract-mode call was not observed.
- One lottery per net and one distribution per net.
- Block attribution used the miner field, `ownerOfOperator` and a `SeatTransferred` replay. It is not the production RewardRouter.
- The Hardhat suite was not re-run, so there is no side-by-side comparison.
- Shanghai/Cancun transitions, SurenSale, ServiceStaking, Treasury spending, slashing and appeals were not exercised on Besu.
- Not production-readiness evidence. The production genesis tool, RewardRouter, Verifier service and security audit do not exist yet.
