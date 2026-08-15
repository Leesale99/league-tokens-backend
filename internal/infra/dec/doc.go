// Package dec implements fixed-point decimal arithmetic for the game's in-game
// numeric quantities: Currency (the free-to-play in-game currency — NOT fiat,
// NOT real money), per-team Tokens, and Odds.
//
// It is the only package allowed to perform arithmetic on these values: it
// centralizes shopspring/decimal with round-half-up to 6 decimals
// (NUMERIC(38,6) storage) per ADR-0010.
package dec
