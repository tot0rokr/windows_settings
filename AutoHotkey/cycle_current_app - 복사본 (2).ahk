#Requires AutoHotkey v2.0
#SingleInstance Force
DetectHiddenWindows false

; === 설정 ===
global CYCLE_TIMEOUT := 1200  ; ms: 이 시간 안에 연속 입력이면 같은 스냅샷으로 계속 순회

; === 단축키 ===
; 1) 최소화 창 제외 순회
!`::CycleCurrentAppWindows( 1, true)    ; Alt+`
!+`::CycleCurrentAppWindows(-1, true)   ; Alt+Shift+`

; 2) 최소화 창 포함 순회
^!`::CycleCurrentAppWindows( 1, false)  ; Ctrl+Alt+`
^!+`::CycleCurrentAppWindows(-1, false) ; Ctrl+Alt+Shift+`

; === 내부 상태: 모드별 + exe별로 스냅샷 유지 ===
global gCycles := Map() ; key = mode "|" exe, value = Map("list", Array, "idx", int, "tick", int)

CycleCurrentAppWindows(dir := 1, skipMinimized := true) {
    global gCycles, CYCLE_TIMEOUT

    curHwnd := WinGetID("A")
    exe     := WinGetProcessName("ahk_id " curHwnd)
    now     := A_TickCount

    modeKey := (skipMinimized ? "SKIPMIN" : "INCLMIN")
    key     := modeKey "|" exe

    reuse := false
    if gCycles.Has(key) {
        st := gCycles[key]
        if (now - st["tick"] <= CYCLE_TIMEOUT) {
            reuse := true
        }
    }

    if !reuse {
        list := BuildWindowSnapshot(exe, skipMinimized)
        if (list.Length < 2)
            return

        st := Map()
        st["list"] := list
        idxNow := IndexOf(list, curHwnd)
        st["idx"]  := idxNow ? idxNow : 1
        st["tick"] := now
        gCycles[key] := st
    } else {
        st := gCycles[key]
    }

    ; 정리(닫힌 창, 그리고 skip 모드면 최소화된 창도 제거)
    st["list"] := PruneList(st["list"], skipMinimized)
    if (st["list"].Length < 2) {
        gCycles.Delete(key)
        return
    }

    ; 현재 포커스 기준 인덱스 재확인
    idx := IndexOf(st["list"], WinGetID("A"))
    if (!idx)
        idx := st["idx"]

    next := FindNextIndex(st["list"], idx, dir, skipMinimized)
    if (!next) {
        st["tick"] := now
        return
    }

    target := st["list"][next]

    ; 포함 모드면 최소화된 창도 실제로 열어주기
    if (!skipMinimized && IsMinimized(target))
        WinRestore("ahk_id " target)

    WinActivate("ahk_id " target)

    st["idx"]  := next
    st["tick"] := now
}

BuildWindowSnapshot(exe, skipMinimized) {
    wins := WinGetList("ahk_exe " exe) ; 현재 시점 스냅샷(MRU/Z-order)
    out := []
    for , w in wins {
        if !IsAltTabWindow(w)
            continue
        if (skipMinimized && IsMinimized(w))
            continue
        out.Push(w)
    }
    return out
}

PruneList(list, skipMinimized) {
    out := []
    seen := Map()
    for , w in list {
        if !WinExist("ahk_id " w)
            continue
        if (skipMinimized && IsMinimized(w))
            continue
        k := w . ""
        if seen.Has(k)
            continue
        seen[k] := true
        out.Push(w)
    }
    return out
}

FindNextIndex(list, idx, dir, skipMinimized) {
    n := list.Length
    tries := 0
    j := idx
    while (tries < n) {
        j += dir
        if (j > n)
            j := 1
        else if (j < 1)
            j := n

        hwnd := list[j]
        if !WinExist("ahk_id " hwnd) {
            tries++
            continue
        }
        if (skipMinimized && IsMinimized(hwnd)) {
            tries++
            continue
        }
        return j
    }
    return 0
}

IsMinimized(hwnd) {
    return (WinGetMinMax("ahk_id " hwnd) = -1)
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
