#!/usr/bin/env bash
# What the compose file's header says, checked from inside the lab's own network and through
# docker exec, which is how the platform's terminal reaches the lab's Python: run by check.sh.
set -euo pipefail
: "${NET:?run through test/check.sh}"
: "${CID:?run through test/check.sh}"
probe() { docker run --rm --network "$NET" lab-check-probe bash -c "$1"; }
run() { docker exec "$CID" "$@"; }
has() { grep -Eq "$1" <<<"$2" || { echo "no match for '$1' in: $2" >&2; exit 1; }; }

echo "- JupyterLab answers with no token, and the shop Preview answers on 8000"
probe '
set -eu
code=$(curl -s -o /dev/null -w "%{http_code}" http://jupyter:8888/lab)
[ "$code" = 200 ] || { echo "JupyterLab answered $code" >&2; exit 1; }
curl -fs http://jupyter:8888/api/contents | grep -q "start.ipynb" || { echo "no start.ipynb" >&2; exit 1; }
curl -fs -H "Host: someone-8888.example.com" -H "Origin: https://someone-8888.example.com" \
  http://jupyter:8888/api/kernelspecs | grep -q python3 || { echo "a proxied host is refused" >&2; exit 1; }
curl -fs http://jupyter:8000/ | grep -q "<title>Teapot Corner</title>" || { echo "the preview is not the shop" >&2; exit 1; }
curl -fs http://jupyter:8000/checkout.html | grep -q "Error 7" || { echo "no checkout page" >&2; exit 1; }
curl -fs http://jupyter:8000/style.css | grep -q "outline: none" || { echo "no style.css" >&2; exit 1; }
curl -fs -o /dev/null http://jupyter:8000/logo.png || { echo "no logo.png" >&2; exit 1; }
echo "- no way out to the internet"
if curl -s -m 4 -o /dev/null https://example.com; then echo "the lab reached the internet" >&2; exit 1; fi
'

echo "- the work folder holds the shop, the data, the notes, the notebook and the step scripts"
run ls shop/index.html shop/checkout.html shop/style.css shop/logo.png shop/blue.png shop/green.png shop/red.png \
  sessions.csv sus.csv notes.md start.ipynb \
  steps/contrast.py steps/audit.py steps/tasks.py steps/sus.py steps/errors.py steps/fix.py >/dev/null
test "$(run wc -l sessions.csv | awk '{print $1}')" = 49 || { echo "sessions.csv is not 12 people by 4 tasks" >&2; exit 1; }
test "$(run wc -l sus.csv | awk '{print $1}')" = 13 || { echo "sus.csv is not 12 people" >&2; exit 1; }
test "$(run grep -c '^- P' notes.md)" = 8 || { echo "notes.md is not eight observations" >&2; exit 1; }

echo "- contrast.py: five rules, one enough and four too low, with the numbers the lesson names"
out=$(run python3 steps/contrast.py)
has "^body +#999999 on #ffffff ratio 2\.85 too low$" "$out"
has "^h1 +#222222 on #ffffff ratio 15\.91 enough$" "$out"
has "^a +#9fbfe8 on #ffffff ratio 1\.89 too low$" "$out"
has "^\.error +#ff9999 on #ffffff ratio 2\.05 too low$" "$out"
has "^\.buy +#ffffff on #f2c94c ratio 1\.59 too low$" "$out"

echo "- audit.py: the faults the test found, counted"
out=$(run python3 steps/audit.py)
for want in "images without alt text: 3 of 4" "links with vague text: 5 of 6" "inputs without a label: 3 of 4" \
  "links with vague text: 1 of 1" "error messages that are only a code: 1" \
  "rules that remove the focus outline: 1" "font sizes under 14 px: 2 of 3"; do
  has "^  $want$" "$out"
done

echo "- tasks.py: the fix_error task is the one people fail"
out=$(run python3 steps/tasks.py)
has "^find_teapot +100\.0 +27\.5$" "$out"
has "^add_to_basket +83\.0 +36\.5$" "$out"
has "^fill_form +92\.0 +97\.5$" "$out"
has "^fix_error +50\.0 +110\.0$" "$out"

echo "- sus.py: twelve scores and a mean of 55.0"
out=$(run python3 steps/sus.py)
has "^mean score: 55\.0$" "$out"
test "$(grep -Ec '^ *P[0-9]+ +[0-9.]+$' <<<"$out")" = 12 || { echo "not twelve scores: $out" >&2; exit 1; }
has "^ *P1 +80\.0$" "$out"
has "^ *P8 +32\.5$" "$out"

echo "- errors.py: fix_error has the most mistakes, 34"
out=$(run python3 steps/errors.py)
has "^fix_error +34$" "$out"
has "^most errors: fix_error$" "$out"

echo "- fix.py: says nothing is fixed, then audits and checks contrast"
out=$(run python3 steps/fix.py)
has "^Nothing is fixed here" "$out"
has "images without alt text: 3 of 4" "$out"
has "^contrast$" "$out"
has "ratio 2\.85 too low" "$out"

echo "- a change saved to the shop shows in the Preview and in the audit"
run sed -i 's|<img src="red.png">|<img src="red.png" alt="Red teapot">|' shop/index.html
probe 'curl -fs http://jupyter:8000/ | grep -q "alt=\"Red teapot\"" || { echo "the preview did not change" >&2; exit 1; }'
run python3 steps/audit.py | grep -q "images without alt text: 2 of 4" || { echo "the audit did not change" >&2; exit 1; }

echo "- the starter notebook runs from top to bottom inside the memory limit"
run jupyter nbconvert --to notebook --execute start.ipynb --output /tmp/ran.ipynb >/dev/null 2>&1 \
  || { echo "start.ipynb does not run" >&2; exit 1; }
echo "  ok"
