:" Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab "
:" "
:" This program is free software: you can redistribute it and/or modify "
:" it under the terms of the GNU Affero General Public License as published by "
:" the Free Software Foundation, either version 3 of the License, or "
:" (at your option) any later version. "
:" "
:" This program is distributed in the hope that it will be useful, "
:" but WITHOUT ANY WARRANTY; without even the implied warranty of "
:" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the "
:" GNU Affero General Public License for more details. "
:" "
:" You should have received a copy of the GNU Affero General Public License "
:" along with this program.  If not, see <https://www.gnu.org/licenses/>. "

:" Klong (kg) Flat-Array Interchange Adapter for SOVEREIGN-RH-LOCK "
:" Implements SoA candidate operations matching klong/array_contract.md "

:" Status constants "
ACTIVE::1
PRUNED::2
INVALID::-1

:" Spectral interval mask: 1 if lo <= lam <= hi, else 0 "
sinterval::{[lam lo hi];lam::x;lo::y;hi::z;(lam>=lo)&(lam<=hi)}

:" Residual threshold mask: (res <= tol) & (|zr - 0.5| <= ltol) "
rmask::{[zr res tol ltol];zr::x;res::y;tol::z;ltol::1;:(res<=tol)&(abs(zr-0.5)<=ltol)}

:" Priority score J(C) = w1*ent + w2*nov + w3*prog - w4*res "
jscore::{[ent nov prog res w];ent::x;nov::y;prog::z;res::w1;w::w2;(w@0*ent)+(w@1*nov)+(w@2*prog)-(w@3*res)}

:" Compact array by boolean mask: select elements where m = 1 "
compact::{[a m];a::x;m::y;a@&m}

:" Verify SoA column lengths match N "
validsoa::{[cols n];cols::x;n::#(*cols);&/{(#x)=n}'cols}
