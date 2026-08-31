#!/usr/bin/env bash
# Mini Apps kontraktining web bilan sinxronligini tekshiradi.
#
# Ishlatish: bash scripts/check_mini_apps_contract.sh
# CI namunasi: docs/contracts/mini-apps/ci.md

set -euo pipefail

fail() {
  echo "::error::$1"
  exit 1
}

echo "1) Shartnoma fayllari"
for file in \
  docs/contracts/mini-apps/CONTRACT_VERSION \
  docs/contracts/mini-apps/README.md \
  docs/contracts/mini-apps/open-strategy.md \
  docs/contracts/mini-apps/mini-app-manifest.schema.json; do
  test -f "$file" || fail "$file topilmadi (socialalsamos bilan sinxron emas)"
done

version=$(tr -d '[:space:]' < docs/contracts/mini-apps/CONTRACT_VERSION)
echo "   kontrakt versiyasi: $version"
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || fail "CONTRACT_VERSION semver formatida bo'lishi kerak"

strategy=lib/features/miniapps/domain/mini_app_open_strategy.dart

echo "2) Timeout qiymatlari web bilan mos"
grep -q 'kMiniAppDirectTimeout = Duration(milliseconds: 8000)' "$strategy" \
  || fail "direct timeout 8000 ms bo'lishi kerak"
grep -q 'kMiniAppProxyTimeout = Duration(milliseconds: 15000)' "$strategy" \
  || fail "proxy timeout 15000 ms bo'lishi kerak"

echo "3) Framing bloklangan hostlar ro'yxati mavjud"
grep -q 'kFramingBlockedHosts' "$strategy" \
  || fail "framing bloklangan hostlar ro'yxati o'chirilgan"

echo "4) Kategoriyalar xardkod qilinmaganligi"
if grep -rn 'miniAppCategories' lib/features/miniapps/data/mini_apps_feed_repository.dart; then
  fail "kategoriyalar faqat mini_app_categories jadvalidan olinadi"
fi

echo "5) Ranking klientda takrorlanmaganligi"
if grep -rn 'sort((' lib/features/miniapps/data/mini_apps_feed_repository.dart; then
  fail "tartiblash faqat serverda (mini_apps_feed RPC) bajariladi"
fi

echo
echo "Barcha kontrakt tekshiruvlari muvaffaqiyatli o'tdi."
