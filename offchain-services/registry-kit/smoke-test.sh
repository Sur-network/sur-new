#!/usr/bin/env bash
# آزمون دودی رجیستری سور (روی خود میزبان). رمز را از push.secret می‌خواند و چاپ نمی‌کند.
# پس از آزمون، تصویر آزمایشی را نگه نمی‌دارد: با WIPE=1 حجم داده پاک و رجیستری دوباره بالا می‌آید.
set -u
cd "$(dirname "$0")"
READ=${READ:-127.0.0.1:5000}
PUSH=${PUSH:-127.0.0.1:5001}
IMG=${IMG:-nginx:alpine}          # ایمیجی که از قبل روی میزبان هست (دانلود نمی‌کند)
pass=0; fail=0
ok()  { echo "PASS  $1"; pass=$((pass+1)); }
bad() { echo "FAIL  $1"; fail=$((fail+1)); }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

[ "$(code "http://$READ/v2/")" = 200 ] && ok "خواندن: GET /v2/ بدون ورود ۲۰۰" || bad "خواندن: GET /v2/"
c=$(code -X POST "http://$READ/v2/test/blobs/uploads/"); { [ "$c" = 403 ] || [ "$c" = 405 ]; } && ok "خواندن: نوشتن رد شد ($c)" || bad "خواندن: نوشتن رد نشد ($c)"
c=$(code -X DELETE "http://$READ/v2/test/manifests/sha256:0000000000000000000000000000000000000000000000000000000000000000"); { [ "$c" = 403 ] || [ "$c" = 405 ]; } && ok "خواندن: حذف رد شد ($c)" || bad "خواندن: حذف رد نشد ($c)"
[ "$(code "http://$PUSH/v2/")" = 401 ] && ok "نوشتن: بدون ورود ۴۰۱" || bad "نوشتن: بدون ورود ۴۰۱ نشد"
[ "$(code -u ci:wrong "http://$PUSH/v2/")" = 401 ] && ok "نوشتن: رمز غلط ۴۰۱" || bad "نوشتن: رمز غلط ۴۰۱ نشد"
[ "$(code -u "ci:$(cat push.secret)" "http://$PUSH/v2/")" = 200 ] && ok "نوشتن: ورود درست ۲۰۰" || bad "نوشتن: ورود درست ۲۰۰ نشد"

CFG=$(mktemp -d); export DOCKER_CONFIG=$CFG
trap 'rm -rf "$CFG"; docker rmi "$PUSH/test/img:t" "$READ/test/img:t" >/dev/null 2>&1' EXIT
cat push.secret | docker login "$PUSH" -u ci --password-stdin >/dev/null 2>&1 && ok "docker login روی در نوشتن" || bad "docker login"
docker tag "$IMG" "$PUSH/test/img:t"
docker push "$PUSH/test/img:t" >/dev/null 2>&1 && ok "push با ورود" || bad "push با ورود"
SRC=$(docker image inspect "$IMG" --format '{{.Id}}')
docker rmi "$PUSH/test/img:t" >/dev/null 2>&1
docker pull "$READ/test/img:t" >/dev/null 2>&1 && ok "pull از در خواندن (بدون ورود)" || bad "pull از در خواندن"
GOT=$(docker image inspect "$READ/test/img:t" --format '{{.Id}}' 2>/dev/null)
[ -n "$GOT" ] && [ "$GOT" = "$SRC" ] && ok "هش ایمیج دریافتی با اصل یکی است" || bad "هش ایمیج یکی نیست"
docker logout "$PUSH" >/dev/null 2>&1

if [ "${WIPE:-0}" = 1 ]; then
  docker compose down -v >/dev/null 2>&1 && docker compose up -d >/dev/null 2>&1 && ok "حجم آزمایشی پاک و رجیستری دوباره بالا آمد" || bad "پاک‌سازی حجم"
fi
echo "نتیجه: $pass گذشت، $fail شکست"
[ "$fail" = 0 ]
