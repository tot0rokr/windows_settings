#Requires AutoHotkey v2.0
; ========= 기본 공통 =========
; CapsLock ↔ Left Ctrl
;SC03A::SC01D
;SC01D::SC03A
CapsLock::LCtrl
LCtrl::CapsLock

; Esc ↔ `~   (Shift+Esc = ~)
; SC001::SC029
; SC029::SC001
Esc::SC029
SC029::Esc

; ========= US 배열(엔터 위의 \|) =========
; Backspace → \| → Right Shift → Backspace
; SC00E::SC02B
; SC02B::RShift
; RShift::SC00E
Backspace::SC02B
SC02B::RShift
RShift::Backspace