# SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
# Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
#
# architecture.awk: renders the box-and-arrow spec in architecture.txt as SVG.
# usage: awk -f architecture.awk architecture.txt > architecture.svg
BEGIN {
  fill["in"] = "#f3f3f3"; line["in"] = "#888"
  fill["c"] = "#e3ecfa"; line["c"] = "#1f4e9a"
  fill["f"] = "#e6f4ea"; line["f"] = "#2e7d32"
  fill["pl"] = "#fdf1e2"; line["pl"] = "#c06a00"
  fill["lean"] = "#f1e8f8"; line["lean"] = "#6a3d9a"
  fill["test"] = "#fbe9e9"; line["test"] = "#b33"
}
/^#/ || NF == 0 { next }
$1 == "size" { SW = $2; SH = $3; next }
$1 == "title" { sub(/^title +/, ""); title = $0; next }
$1 == "box" {
  id = $2; bx[id] = $3; by[id] = $4; bw[id] = $5; bh[id] = $6; bs[id] = $7; order[++nb] = id
  s = $0; sub(/^[^|]*\| */, "", s); nl[id] = split(s, parts, / *\| */)
  for (i = 1; i <= nl[id]; i++) txt[id, i] = parts[i]
  next
}
$1 == "edge" { ne++; ef[ne] = $2; et[ne] = $3; s = $0; sub(/^edge +[^ ]+ +[^ ]+ */, "", s); el[ne] = s; next }
function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
END {
  printf "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\" font-family=\"sans-serif\" font-size=\"11\">\n", SW, SH, SW, SH
  printf "<defs><marker id=\"a\" viewBox=\"0 0 8 8\" refX=\"7\" refY=\"4\" markerWidth=\"7\" markerHeight=\"7\" orient=\"auto\"><path d=\"M0 0L8 4L0 8z\" fill=\"#555\"/></marker></defs>\n"
  printf "<rect width=\"%d\" height=\"%d\" fill=\"#fff\"/>\n<text x=\"%d\" y=\"22\" text-anchor=\"middle\" font-size=\"13\">%s</text>\n", SW, SH, SW / 2, esc(title)
  for (e = 1; e <= ne; e++) {
    a = ef[e]; b = et[e]
    if (bx[b] >= bx[a] + bw[a]) {
      x1 = bx[a] + bw[a]; y1 = by[a] + bh[a] / 2; x2 = bx[b] - 2; y2 = by[b] + bh[b] / 2
      y2 = y1; if (y2 < by[b] + 8) y2 = by[b] + 8; if (y2 > by[b] + bh[b] - 8) y2 = by[b] + bh[b] - 8
      mx = (x1 + x2) / 2
      printf "<path d=\"M%d %d C%.1f %d %.1f %d %d %d\" fill=\"none\" stroke=\"#555\" marker-end=\"url(#a)\"/>\n", x1, y1, mx, y1, mx, y2, x2, y2
      if (el[e] != "") printf "<text x=\"%.1f\" y=\"%d\" text-anchor=\"middle\" font-size=\"9\" fill=\"#555\">%s</text>\n", mx, (y1 < y2 ? y1 : y2) - 5, esc(el[e])
    } else {
      x1 = bx[a] + bw[a] / 2; y1 = by[a] + bh[a]; x2 = bx[b] + bw[b] / 2; y2 = by[b] - 2
      printf "<line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" stroke=\"#555\" marker-end=\"url(#a)\"/>\n", x1, y1, x2, y2
    }
  }
  for (k = 1; k <= nb; k++) {
    id = order[k]; st = bs[id]
    printf "<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" rx=\"6\" fill=\"%s\" stroke=\"%s\"/>\n", bx[id], by[id], bw[id], bh[id], fill[st], line[st]
    top = by[id] + bh[id] / 2 - (nl[id] - 1) * 7 + 4
    for (i = 1; i <= nl[id]; i++)
      printf "<text x=\"%.1f\" y=\"%d\" text-anchor=\"middle\"%s>%s</text>\n", bx[id] + bw[id] / 2, top + (i - 1) * 14, (i == 1 ? " font-weight=\"bold\"" : " fill=\"#444\""), esc(txt[id, i])
  }
  printf "</svg>\n"
}
