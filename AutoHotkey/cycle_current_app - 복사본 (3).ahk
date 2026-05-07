#Requires AutoHotkey v2.0
#SingleInstance Force
DetectHiddenWindows false

; === 설정 ===
global CYCLE_TIMEOUT := 1200  ; ms: 이 시간 안에 연속 입력이면 같은 스냅샷으로 계속 순회

; =========================
; 단축키
; =========================

; [1] 현재 앱(같은 exe) 창 순회
; - 최소화 제외
!`::CycleCurrentAppWindows( 1, true)
!+`::CycleCurrentAppWindows(-1, true)

; - 최소화 포함
^!`::CycleCurrentAppWindows( 1, false)
^!+`::CycleCurrentAppWindows(-1, false)

; [2] 앱 단위 순회 (각 앱의 대표 창 1개만)
; - 최소화 제외
#`::CycleApps( 1, true)
#+`::CycleApps(-1, true)

; - 최소화 포함
^#`::CycleApps( 1, false)
^#+`::CycleApps(-1, false)

; =========================
; 내부 상태: scope|mode|exe 로 스냅샷 유지
; =========================
global gCycles := Map() ; key -> Map("list", Array, "idx", int, "tick", int)

GetStateKey(scope, skipMinimized, exe := "") {
    modeKey := skipMinimized ? "SKIPMIN" : "INCLMIN"
    return scope "|" modeKey "|" exe
}

; =========================
; (A) 현재 앱 창 순회
; =========================
CycleCurrentAppWindows(dir := 1, skipMinimized := true) {
    global gCycles, CYCLE_TIMEOUT

    curHwnd := WinGetID("A")
    exe     := WinGetProcessName("ahk_id " curHwnd)
    now     := A_TickCount

    key := GetStateKey("CURAPP", skipMinimized, exe)

    reuse := false
    if gCycles.Has(key) {
        st := gCycles[key]
        if (now - st["tick"] <= CYCLE_TIMEOUT)
            reuse := true
    }

    if !reuse {
        list := BuildWindowSnapshotForExe(exe, skipMinimized)
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

    st["list"] := PruneList(st["list"], skipMinimized)
    if (st["list"].Length < 2) {
        gCycles.Delete(key)
        return
    }

    idx := IndexOf(st["list"], WinGetID("A"))
    if (!idx)
        idx := st["idx"]

    next := FindNextIndex(st["list"], idx, dir, skipMinimized)
    if (!next) {
        st["tick"] := now
        return
    }

    target := st["list"][next]
    if (!skipMinimized && IsMinimized(target))
        WinRestore("ahk_id " target)
    WinActivate("ahk_id " target)

    st["idx"]  := next
    st["tick"] := now
}

BuildWindowSnapshotForExe(exe, skipMinimized) {
    wins := WinGetList("ahk_exe " exe) ; MRU/Z-order 스냅샷
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

; =========================
; (B) 앱 단위 순회: 각 앱 대표 창 1개만
; =========================
CycleApps(dir := 1, skipMinimized := true) {
    global gCycles, CYCLE_TIMEOUT

    curHwnd := WinGetID("A")
    curExe  := WinGetProcessName("ahk_id " curHwnd)
    now     := A_TickCount

    key := GetStateKey("APPS", skipMinimized, "")  ; exe 없이 모드별로만 유지

    reuse := false
    if gCycles.Has(key) {
        st := gCycles[key]
        if (now - st["tick"] <= CYCLE_TIMEOUT)
            reuse := true
    }

    if !reuse {
        list := BuildAppSnapshot(skipMinimized) ; 각 exe당 첫 창 1개
        if (list.Length < 2)
            return

        st := Map()
        st["list"] := list
        idxNow := IndexOfExe(list, curExe)
        st["idx"]  := idxNow ? idxNow : 1
        st["tick"] := now
        gCycles[key] := st
    } else {
        st := gCycles[key]
    }

    st["list"] := PruneList(st["list"], skipMinimized)
    if (st["list"].Length < 2) {
        gCycles.Delete(key)
        return
    }

    ; 현재 창이 대표창이 아니어도 "현재 exe" 위치로 잡기
    exeNow := WinGetProcessName("ahk_id " WinGetID("A"))
    idx := IndexOfExe(st["list"], exeNow)
    if (!idx)
        idx := st["idx"]

    next := FindNextIndex(st["list"], idx, dir, skipMinimized)
    if (!next) {
        st["tick"] := now
        return
    }

    target := st["list"][next]
    if (!skipMinimized && IsMinimized(target))
        WinRestore("ahk_id " target)
    WinActivate("ahk_id " target)

    st["idx"]  := next
    st["tick"] := now
}

BuildAppSnapshot(skipMinimized) {
    wins := WinGetList() ; 전체 top-level
    out := []
    seenExe := Map()
    for , w in wins {
        if !IsAltTabWindow(w)
            continue
        if (skipMinimized && IsMinimized(w))
            continue

        exe := WinGetProcessName("ahk_id " w)
        if seenExe.Has(exe)
            continue

        seenExe[exe] := true
        out.Push(w) ; 이 exe의 "첫 번째(대표) 창"
    }
    return out
}

IndexOfExe(list, exe) {
    for i, hwnd in list {
        if WinExist("ahk_id " hwnd) {
            if (WinGetProcessName("ahk_id " hwnd) = exe)
                return i
        }
    }
    return 0
}

; =========================
; 공통 유틸
; =========================
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
