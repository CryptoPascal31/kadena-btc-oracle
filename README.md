# Kadena BTC Oracle

## Intro
The objective of that module is to be used as a "0 trust" entropy source.

Reporters reports mined a BTC blocks headers.

Consumers use the hash of these blocks as an entropy source.

The Smart-Contracts verifies the authenticity of the Block Header. As such reporters don't need special privileges.

And consumers can trust the reporters because the authenticity if guaranteed by the PoW and Hash Power of the Bitcoin network.

Once at least one single reported header has been confirmed to be legit, we can assume that the subsequent headers are legit too.


## Reporting

The contract must be initialized using the function `(init-block header)` by a trusted party. This first report will only pass lightweight verification.


Then anyone can submit a block with `(report-block header)`. Header must be encoded in Hex.

This functions does the following verifications:
  - Check the previous-block field. The previous block must have already been reported.
  - Check the target field against the previous block. The target field must meet Bitcoin Requirements: Change only every 2016 blocks, and only within a range of [0.25 - 4.0]
  - Recompute the SHA256 hash and compare with the target.

The module supports orphan blocks, and accept forks to a depth of 2.


## Consuming

To select a specific block and the corresponding hash with an unequivocal and efficient way, the consumer must choose some requirements
  - The minimum height
  - The minimum timestamp. For maximum security, the consumer must consider an allowed  2 hours delta between the block's timestamp and the mining time.
  - A minimum number of confirmations: For BTC, a value of 1 should be OK since orphaned blocks are scarce, and orphaned chains in practice never happens.

The function `(select-block after-height after-time confirmations)` can be used for that purpose. The function  `(select-hash after-height after-time confirmations)` can be used to only retrieve the hash.

## Util functions

TBC
