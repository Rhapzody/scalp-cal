#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "$#" -eq 0 ] || [ "$1" = "all" ]; then
  for runner in scripts/tests/*.sh; do
    printf '\nTesting %s\n' "$(basename "$runner" .sh)"
    sh "$runner"
  done
else
  for product in "$@"; do
    case "$product" in
      engulf-imbalance-flow|wick-hunt-telegram-ea|wick-hunt-anchor) printf '%s: no tests configured (created without tests as requested).\n' "$product"; continue ;;
      scalp-calculator|instant-engulf|tv-style-macd|pa-reversal|macd-swing-count|trade-journal|engulf-flow|imbalance-flow|macd-zone-pullback|macd-zone-trader|trend-sweep-reclaim|trend-sweep-trader) ;;
      opening-range-retest|opening-range-trader|wick-hunt-sr-flow) ;;
      *) printf 'Unknown product: %s\n' "$product" >&2; exit 2 ;;
    esac
    sh "scripts/tests/$product.sh"
  done
fi
