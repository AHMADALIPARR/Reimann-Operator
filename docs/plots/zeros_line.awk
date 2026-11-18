# SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
# Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
#
# zeros_line.awk: SVG of the oracle zeros rho = 1/2 + i t on the critical line,
# with the zero-counting staircase N(T) against the Riemann-von Mangoldt main term.
# usage: awk -f zeros_line.awk data/zeta_zeros_oracle.txt > zeros_critical_line.svg
# Each oracle line is "[k] t"; the last field is the ordinate t.
{ n++; t[n] = $NF + 0 }
function X(v) { return L + (v - 0) / TMAX * W }
function Y2(v) { return T2 + H2 - v / NMAX * H2 }
END {
  pi = atan2(0, -1); TMAX = 850; NMAX = 550
  L = 58; W = 640; T1 = 34; H1 = 70; T2 = 150; H2 = 170
  printf "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"720\" height=\"360\" viewBox=\"0 0 720 360\" font-family=\"sans-serif\" font-size=\"11\">\n"
  printf "<rect width=\"720\" height=\"360\" fill=\"#fff\"/>\n"
  printf "<text x=\"360\" y=\"18\" text-anchor=\"middle\" font-size=\"13\">%d oracle zeros of ζ(s) on the critical line</text>\n", n
  # panel 1: critical strip, sigma vertical, t horizontal
  printf "<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" fill=\"#eef3fb\" stroke=\"#9ab\"/>\n", L, T1, W, H1
  printf "<line x1=\"%d\" y1=\"%.1f\" x2=\"%d\" y2=\"%.1f\" stroke=\"#c33\" stroke-dasharray=\"4 3\"/>\n", L, T1 + H1/2, L + W, T1 + H1/2
  printf "<g fill=\"#1f4e9a\">"
  for (i = 1; i <= n; i++) printf "<circle cx=\"%.1f\" cy=\"%.1f\" r=\"1.3\"/>", X(t[i]), T1 + H1/2
  printf "</g>\n"
  printf "<text x=\"%d\" y=\"%d\" text-anchor=\"end\">σ=1</text><text x=\"%d\" y=\"%.1f\" text-anchor=\"end\">½</text><text x=\"%d\" y=\"%d\" text-anchor=\"end\">0</text>\n", L-4, T1+8, L-4, T1+H1/2+4, L-4, T1+H1
  # panel 2: N(T)
  printf "<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" fill=\"none\" stroke=\"#9ab\"/>\n", L, T2, W, H2
  for (v = 0; v <= 500; v += 100) printf "<text x=\"%d\" y=\"%.1f\" text-anchor=\"end\">%d</text><line x1=\"%d\" x2=\"%d\" y1=\"%.1f\" y2=\"%.1f\" stroke=\"#eee\"/>\n", L-4, Y2(v)+4, v, L, L+W, Y2(v), Y2(v)
  for (v = 0; v <= 800; v += 100) printf "<text x=\"%.1f\" y=\"%d\" text-anchor=\"middle\">%d</text><line x1=\"%.1f\" x2=\"%.1f\" y1=\"%d\" y2=\"%d\" stroke=\"#ccc\"/>\n", X(v), T2+H2+14, v, X(v), X(v), T1+H1, T1+H1+4
  # smooth main term N0(T) = T/2pi log(T/2pi e) + 7/8
  printf "<path fill=\"none\" stroke=\"#c33\" stroke-width=\"1.5\" d=\"M"
  for (v = 10; v <= TMAX; v += 10) { y = v/(2*pi) * log(v/(2*pi*exp(1))) + 7/8; if (y < 0) y = 0; printf "%s%.1f %.1f", (v == 10 ? "" : " L"), X(v), Y2(y) }
  printf "\"/>\n"
  # staircase of the oracle
  printf "<path fill=\"none\" stroke=\"#1f4e9a\" stroke-width=\"1\" d=\"M%.1f %.1f", X(0), Y2(0)
  for (i = 1; i <= n; i++) printf "H%.1fV%.1f", X(t[i]), Y2(i)
  printf "H%.1f\"/>\n", X(TMAX)
  printf "<text x=\"%d\" y=\"%d\" text-anchor=\"middle\">t = Im ρ</text>\n", L + W/2, T2 + H2 + 30
  printf "<text transform=\"translate(16 %d) rotate(-90)\" text-anchor=\"middle\">N(T)</text>\n", T2 + H2/2
  printf "<g><line x1=\"%d\" x2=\"%d\" y1=\"%d\" y2=\"%d\" stroke=\"#1f4e9a\"/><text x=\"%d\" y=\"%d\">oracle count</text>", L+14, L+34, T2+16, T2+16, L+40, T2+20
  printf "<line x1=\"%d\" x2=\"%d\" y1=\"%d\" y2=\"%d\" stroke=\"#c33\" stroke-width=\"1.5\"/><text x=\"%d\" y=\"%d\">T/2π·log(T/2πe) + 7/8</text></g>\n", L+14, L+34, T2+32, T2+32, L+40, T2+36
  printf "</svg>\n"
}
