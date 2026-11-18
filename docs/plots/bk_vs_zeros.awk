# SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
# Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
#
# bk_vs_zeros.awk: spectral barcode of Berry-Keating discretisations against the
# oracle zeros. Every input except the last is a JSON eigenvalue list written by
# `ro eigvalsh`; the last input is data/zeta_zeros_oracle.txt.
# usage: awk -v labels="n = 32,n = 64,n = 128" -v tmax=60 -f bk_vs_zeros.awk ev32.json ev64.json ev128.json data/zeta_zeros_oracle.txt
FNR == 1 { r++; cnt[r] = 0 }
/^\[/ { gsub(/[][ ]/, ""); k = split($0, a, ","); for (i = 1; i <= k; i++) { v = a[i] + 0; if (v > 1e-9 && v <= tmax) val[r, ++cnt[r]] = v }; next }
{ v = $NF + 0; if (v <= tmax) val[r, ++cnt[r]] = v }
function X(v) { return L + v / tmax * W }
END {
  nl = split(labels, lab, ","); lab[r] = "ζ zeros"
  L = 92; W = 600; T = 40; RH = 46
  hgt = T + r * RH + 40
  printf "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"720\" height=\"%d\" viewBox=\"0 0 720 %d\" font-family=\"sans-serif\" font-size=\"11\">\n", hgt, hgt
  printf "<rect width=\"720\" height=\"%d\" fill=\"#fff\"/>\n", hgt
  printf "<text x=\"360\" y=\"18\" text-anchor=\"middle\" font-size=\"13\">Positive Berry–Keating eigenvalues (a=1, b=10, θ=0) vs oracle zeros, 0 &lt; t ≤ %g</text>\n", tmax
  for (q = 1; q <= r; q++) {
    y = T + (q - 1) * RH
    # sort and drop the twofold degeneracy of the discretised spectrum
    m = cnt[q]; for (i = 1; i <= m; i++) w[i] = val[q, i]
    for (i = 2; i <= m; i++) { v = w[i]; j = i - 1; while (j > 0 && w[j] > v) { w[j+1] = w[j]; j-- }; w[j+1] = v }
    d = 0; prev = -1; for (i = 1; i <= m; i++) if (w[i] - prev > 1e-6 * (1 + w[i])) { d++; prev = w[i]; u[d] = w[i] }
    col = (q == r) ? "#c33" : "#1f4e9a"
    printf "<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" fill=\"%s\"/>\n", L, y + 6, W, RH - 12, (q % 2 ? "#f4f7fc" : "#fff")
    printf "<text x=\"%d\" y=\"%d\" text-anchor=\"end\">%s</text><text x=\"%d\" y=\"%d\" text-anchor=\"end\" fill=\"#777\" font-size=\"9\">%d values</text>\n", L - 8, y + RH/2, lab[q], L - 8, y + RH/2 + 12, d
    printf "<g stroke=\"%s\" stroke-width=\"1.6\">", col
    for (i = 1; i <= d; i++) printf "<line x1=\"%.1f\" x2=\"%.1f\" y1=\"%d\" y2=\"%d\"/>", X(u[i]), X(u[i]), y + 9, y + RH - 9
    printf "</g>\n"
  }
  yb = T + r * RH
  printf "<line x1=\"%d\" x2=\"%d\" y1=\"%d\" y2=\"%d\" stroke=\"#9ab\"/>\n", L, L + W, yb, yb
  for (v = 0; v <= tmax; v += 10) printf "<line x1=\"%.1f\" x2=\"%.1f\" y1=\"%d\" y2=\"%d\" stroke=\"#9ab\"/><text x=\"%.1f\" y=\"%d\" text-anchor=\"middle\">%d</text>\n", X(v), X(v), yb, yb + 4, X(v), yb + 16, v
  printf "<text x=\"%d\" y=\"%d\" text-anchor=\"middle\">eigenvalue / Im ρ</text>\n", L + W/2, yb + 32
  printf "</svg>\n"
}
