#Requires AutoHotkey v2.0
#SingleInstance Force
DetectHiddenWindows false

; === 설정 ===
; 이 시간(ms) 안에 연속으로 누르면 "같은 스냅샷"으로 계속 순회
; (너무 짧으면 다시 토글로 느껴질 수 있음)
global CYCLE_TIMEOUT := 1200

; Alt+`  : 현재 앱 창 앞으로 순회
; Alt+Shift+` : 현재 앱 창 뒤로 순회
!`::CycleCurrentAppWindows(1)
!+`::CycleCurrentAppWindows(-1)

; 내부 상태 (스냅샷 유지용)
global gCycle := Map()  ; keys: "exe","list","idx","tick"

CycleCurrentAppWindows(dir := 1) {
    global gCycle, CYCLE_TIMEOUT

    curHwnd := WinGetID("A")
    curExe  := WinGetProcessName("ahk_id " curHwnd)
    now     := A_TickCount

    reuse := false
    if gCycle.Has("exe") {
        if (gCycle["exe"] = curExe) && (now - gCycle["tick"] <= CYCLE_TIMEOUT) {
            reuse := true
        }
    }

    if !reuse {
        list := BuildWindowSnapshot(curExe)
        if (list.Length < 2)
            return

        gCycle["exe"]  := curExe
        gCycle["list"] := list
        gCycle["idx"]  := IndexOf(list, curHwnd) ? IndexOf(list, curHwnd) : 1
        gCycle["tick"] := now
    }

    ; 스냅샷 가져오기
    list := gCycle["list"]

    ; 닫힌 창 등 정리(가끔 필요)
    list := PruneDeadWindows(list)
    if (list.Length < 2) {
        gCycle.Delete("exe"), gCycle.Delete("list"), gCycle.Delete("idx"), gCycle.Delete("tick")
        return
    }
    gCycle["list"] := list

    ; 현재 인덱스 재확인 (포커스가 바뀐 상태일 수 있음)
    idx := IndexOf(list, WinGetID("A"))
    if (!idx)
        idx := gCycle["idx"]

    next := idx + dir
    if (next > list.Length)
        next := 1
    else if (next < 1)
        next := list.Length

    target := list[next]
    if (WinGetMinMax("ahk_id " target) = -1)
        WinRestore("ahk_id " target)
    WinActivate("ahk_id " target)

    gCycle["idx"]  := next
    gCycle["tick"] := now
}

BuildWindowSnapshot(exe) {
    wins := WinGetList("ahk_exe " exe) ; 현재 시점의 MRU/Z-order 스냅샷
    filtered := []
    for , w in wins {
        if IsAltTabWindow(w)
            filtered.Push(w)
    }
    return filtered
}

PruneDeadWindows(list) {
    out := []
    seen := Map()
    for , w in list {
        if WinExist("ahk_id " w) {
            key := w . ""
            if !seen.Has(key) {
                seen[key] := true
                out.Push(w)
            }
        }
    }
    return out
}

IndexOf(arr, val) {
    for i, v in arr
        if (v = val)
            return i
    return 0
}

IsAltTabWindow(hwnd) {
    if !WinExist("ahk_id " hwnd)
        return false

    exStyle := GetWndLong(hwnd, -20) ; GWL_EXSTYLE
    style   := GetWndLong(hwnd, -16) ; GWL_STYLE

    WS_EX_TOOLWINDOW := 0x80
    WS_EX_APPWINDOW  := 0x40000
    WS_DISABLED      := 0x08000000

    if (exStyle & WS_EX_TOOLWINDOW)
        return false
    if (style & WS_DISABLED)
        return false

    owner := DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") ; GW_OWNER=4
    if (owner && !(exStyle & WS_EX_APPWINDOW))
        return false

    return true
}

GetWndLong(hwnd, index) {
    fn := (A_PtrSize = 8) ? "GetWindowLongPtr" : "GetWindowLong"
    return DllCall(fn, "ptr", hwnd, "int", index, "ptr")
}
