# SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
# Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
#
# spacing_gue.awk: histogram of unfolded nearest-neighbour spacings of the oracle
# zeros against the GUE Wigner surmise and the Poisson law.
# Unfolding uses the Riemann-von Mangoldt main term x(t) = t/2pi log(t/2pi e) + 7/8.
# usage: awk -f spacing_gue.awk data/zeta_zeros_oracle.txt > spacing_gue.svg
{ n++; t[n] = $NF + 0 }
function X(s) { return L + s / SMAX * W }
function Y(p) { return T + H - p / PMAX * H }
END {
  pi = atan2(0, -1); SMAX = 3; PMAX = 1.2; BW = 0.15; NB = int(SMAX / BW + 0.5)
  L = 58; W = 620; T = 34; H = 270
  for (i = 1; i <= n; i++) x[i] = t[i]/(2*pi) * log(t[i]/(2*pi*exp(1))) + 7/8
  m = 0; sum = 0
  for (i = 1; i < n; i++) { s[++m] = x[i+1] - x[i]; sum += s[m] }
  mean = sum / m
  for (i = 1; i <= m; i++) { b = int(s[i] / mean / BW); if (b < NB) c[b]++ }
  printf "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"720\" height=\"360\" viewBox=\"0 0 720 360\" font-family=\"sans-serif\" font-size=\"11\">\n"
  printf "<rect width=\"720\" height=\"360\" fill=\"#fff\"/>\n"
  printf "<text x=\"360\" y=\"18\" text-anchor=\"middle\" font-size=\"13\">%d unfolded spacings of the %d oracle zeros (mean %.4f) vs random-matrix laws</text>\n", m, n, mean
  for (v = 0; v <= 1.0001; v += 0.2) printf "<line x1=\"%d\" x2=\"%d\" y1=\"%.1f\" y2=\"%.1f\" stroke=\"#eee\"/><text x=\"%d\" y=\"%.1f\" text-anchor=\"end\">%.1f</text>\n", L, L+W, Y(v), Y(v), L-4, Y(v)+4, v
  for (v = 0; v <= SMAX; v += 0.5) printf "<text x=\"%.1f\" y=\"%d\" text-anchor=\"middle\">%.1f</text>\n", X(v), T+H+14, v
  printf "<g fill=\"#9db7e0\" stroke=\"#1f4e9a\" stroke-width=\"0.6\">"
  for (b = 0; b < NB; b++) { p = c[b] / (m * BW); printf "<rect x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\"/>", X(b*BW), Y(p), X(BW) - L, Y(0) - Y(p) }
  printf "</g>\n"
  printf "<path fill=\"none\" stroke=\"#c33\" stroke-width=\"2\" d=\"M"
  for (k = 0; k <= 150; k++) { v = k * SMAX / 150; p = 32/(pi*pi) * v*v * exp(-4*v*v/pi); printf "%s%.1f %.1f", (k ? " L" : ""), X(v), Y(p) }
  printf "\"/>\n<path fill=\"none\" stroke=\"#555\" stroke-width=\"1.2\" stroke-dasharray=\"5 3\" d=\"M"
  for (k = 0; k <= 150; k++) { v = k * SMAX / 150; p = exp(-v); if (p > PMAX) p = PMAX; printf "%s%.1f %.1f", (k ? " L" : ""), X(v), Y(p) }
  printf "\"/>\n<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" fill=\"none\" stroke=\"#9ab\"/>\n", L, T, W, H
  printf "<text x=\"%d\" y=\"%d\" text-anchor=\"middle\">normalised spacing s</text>\n", L + W/2, T + H + 30
  printf "<text transform=\"translate(16 %d) rotate(-90)\" text-anchor=\"middle\">density p(s)</text>\n", T + H/2
  lx = L + W - 230
  printf "<rect x=\"%d\" y=\"%d\" width=\"14\" height=\"9\" fill=\"#9db7e0\" stroke=\"#1f4e9a\"/><text x=\"%d\" y=\"%d\">oracle zeros (bin %.2f)</text>\n", lx, T+12, lx+22, T+20, BW
  printf "<line x1=\"%d\" x2=\"%d\" y1=\"%d\" y2=\"%d\" stroke=\"#c33\" stroke-width=\"2\"/><text x=\"%d\" y=\"%d\">GUE surmise 32s²/π² · e^(−4s²/π)</text>\n", lx, lx+14, T+32, T+32, lx+22, T+36
  printf "<line x1=\"%d\" x2=\"%d\" y1=\"%d\" y2=\"%d\" stroke=\"#555\" stroke-dasharray=\"5 3\"/><text x=\"%d\" y=\"%d\">Poisson e^(−s)</text>\n", lx, lx+14, T+48, T+48, lx+22, T+52
  printf "</svg>\n"
}
