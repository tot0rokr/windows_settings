#Requires AutoHotkey v2.0
#SingleInstance Force
; #KeyHistory 0
SetWorkingDir A_ScriptDir
; v2에선 SendMode 불필요(기본 SendInput)

; === Globals ===
DesktopCount := 1
CurrentDesktop := 1
LastOpenedDesktop := 1

; === DLL ===
hVirtualDesktopAccessor := DllCall("LoadLibrary", "str", A_ScriptDir "\VirtualDesktopAccessor.dll", "ptr")
IsWindowOnDesktopNumberProc   := DllCall("GetProcAddress", "ptr", hVirtualDesktopAccessor, "astr", "IsWindowOnDesktopNumber",   "ptr")
MoveWindowToDesktopNumberProc := DllCall("GetProcAddress", "ptr", hVirtualDesktopAccessor, "astr", "MoveWindowToDesktopNumber", "ptr")
GoToDesktopNumberProc         := DllCall("GetProcAddress", "ptr", hVirtualDesktopAccessor, "astr", "GoToDesktopNumber",         "ptr")

; === Main ===
SetKeyDelay 75
mapDesktopsFromRegistry()
OutputDebug "[loading] desktops: " DesktopCount " current: " CurrentDesktop

#Include "%A_ScriptDir%\desktop_switcher_config.ahk"
return

; =========================
; === Helper / Internals ==
; =========================


mapDesktopsFromRegistry() {
    global CurrentDesktop, DesktopCount

    ; 기본값 (GUID 16바이트 = 32 hex)
    IdLenBytes := 16
    IdLength   := 32

    SessionId := getSessionId()

    ; --- 현재 데스크톱 GUID 읽기 (Buffer 또는 hex 문자열 가능) ---
    currentRaw := ""
    try {
        currentRaw := RegRead("HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops", "CurrentVirtualDesktop")
    } catch {
        try {
            currentRaw := RegRead("HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\" SessionId "\VirtualDesktops", "CurrentVirtualDesktop")
        } catch {
            currentRaw := ""
        }
    }

    currentBuf := 0
    currentHex := ""
    if IsObject(currentRaw) {
        ; Buffer
        currentBuf := currentRaw
        IdLenBytes := currentBuf.Size
        IdLength   := IdLenBytes * 2
    } else if (currentRaw) {
        ; 문자열(hex)
        currentHex := RegExReplace(currentRaw, "[^A-Fa-f0-9]")
        IdLength   := StrLen(currentHex)
        IdLenBytes := IdLength // 2
    }

    ; --- 전체 데스크톱 GUID 배열 읽기 (Buffer 또는 hex 문자열 가능) ---
    desktopRaw := ""
    try {
        desktopRaw := RegRead("HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops", "VirtualDesktopIDs")
    } catch {
        desktopRaw := ""
    }

    ; 값이 없으면 데스크톱 1개로 판단
    if (!desktopRaw) {
        DesktopCount := 1
        return
    }

    ; --- 개수 계산 & 현재 인덱스 찾기 ---
    if IsObject(desktopRaw) {
        ; Buffer 케이스
        DesktopCount := (IdLenBytes > 0) ? Floor(desktopRaw.Size / IdLenBytes) : 1
        if (currentBuf && DesktopCount > 0) {
            loop DesktopCount {
                i := A_Index - 1
                same := true
                loop IdLenBytes {
                    if NumGet(desktopRaw, i*IdLenBytes + A_Index - 1, "UChar")
                        != NumGet(currentBuf, A_Index - 1, "UChar") {
                        same := false
                        break
                    }
                }
                if same {
                    CurrentDesktop := i + 1
                    break
                }
            }
        }
    } else {
        ; 문자열(hex) 케이스
        desktopHex := RegExReplace(desktopRaw, "[^A-Fa-f0-9]")
        if (IdLength <= 0) {
            DesktopCount := 1
            return
        }
        DesktopCount := Floor(StrLen(desktopHex) / IdLength)

        if (currentHex && DesktopCount > 0) {
            loop DesktopCount {
                i := A_Index - 1
                iter := SubStr(desktopHex, i*IdLength + 1, IdLength)
                if (StrCompare(iter, currentHex, true) = 0) {
                    CurrentDesktop := i + 1
                    break
                }
            }
        }
    }
}

getSessionId() {
    pid := DllCall("GetCurrentProcessId", "UInt")
    if !pid {
        OutputDebug "Error getting current process id. LastError=" A_LastError
        return 0
    }
    sessionId := 0
    ok := DllCall("ProcessIdToSessionId", "UInt", pid, "UInt*", sessionId)
    if !ok {
        OutputDebug "Error getting session id. LastError=" A_LastError
        return 0
    }
    return sessionId
}

_switchDesktopToTarget(targetDesktop) {
    global CurrentDesktop, DesktopCount, LastOpenedDesktop

    if (targetDesktop > DesktopCount || targetDesktop < 1 || targetDesktop == CurrentDesktop) {
        OutputDebug "[invalid] target: " targetDesktop " current: " CurrentDesktop
        return
    }

    LastOpenedDesktop := CurrentDesktop

    ; 깜빡임 방지용 작업 표시줄 포커싱
    taskbarHwnd := DllCall("FindWindow", "str", "Shell_TrayWnd", "ptr", 0, "ptr")
    if taskbarHwnd
        DllCall("SetForegroundWindow", "ptr", taskbarHwnd)

    DllCall(GoToDesktopNumberProc, "int", targetDesktop - 1)
    focusTheForemostWindow(targetDesktop)
}

updateGlobalVariables() {
    mapDesktopsFromRegistry()
}

switchDesktopByNumber(targetDesktop) {
    updateGlobalVariables()
    _switchDesktopToTarget(targetDesktop)
}

switchDesktopToLastOpened() {
    global LastOpenedDesktop
    updateGlobalVariables()
    _switchDesktopToTarget(LastOpenedDesktop)
}

switchDesktopToRight() {
    global CurrentDesktop, DesktopCount
    updateGlobalVariables()
    _switchDesktopToTarget(CurrentDesktop == DesktopCount ? 1 : CurrentDesktop + 1)
}

switchDesktopToLeft() {
    global CurrentDesktop, DesktopCount
    updateGlobalVariables()
    _switchDesktopToTarget(CurrentDesktop == 1 ? DesktopCount : CurrentDesktop - 1)
}

focusTheForemostWindow(targetDesktop) {
    ; 데스크톱 전환 직후엔 창 열거/포커스가 흔들릴 수 있으니 짧게 재시도
    ; 총 ~150ms 내에서 5회 시도 (필요하면 숫자 살짝 키워도 됨)
    attempts := 5
    loop attempts {
        foremost := getForemostWindowIdOnDesktop(targetDesktop)
        if isWindowNonMinimized(foremost) {
            ; WinActivate가 SetForegroundWindow보다 성공률 높음(입력 큐/포커스 규칙)
            try {
                WinActivate "ahk_id " foremost
            } catch {
                ; 혹시 실패하면 SetForegroundWindow로 보조 시도
                try DllCall("SetForegroundWindow", "ptr", foremost)
            }
            return
        }
        Sleep 30
    }
    ; 여기까지 왔으면 포커스 줄 창이 없음(바탕화면만 있는 경우 등). 그냥 종료.
}

; === 안전 헬퍼 ===
winIsAlive(hwnd) {
    return hwnd && WinExist("ahk_id " hwnd) ; 존재/가시성 여부와 무관, 유효 핸들인지 체크
}

isWindowNonMinimized(hwnd) {
    if !winIsAlive(hwnd)
        return false
    try {
        mm := WinGetMinMax("ahk_id " hwnd) ; -1=최소화, 0=보통, 1=최대화
        return (mm != -1)
    } catch {
        ; 대상 창이 사라졌거나 아직 탐지 안 됨
        return false
    }
}

getForemostWindowIdOnDesktop(n) {
    n -= 1  ; DLL은 0-index
    ; 가장 위에 있는 창부터 열거됨 (v2 기본)
    for hwnd in WinGetList() {
        ; 죽은 핸들 거르기
        if !winIsAlive(hwnd)
            continue
        onDesk := DllCall(IsWindowOnDesktopNumberProc, "ptr", hwnd, "UInt", n, "int")
        if (onDesk = 1) {
            return hwnd
        }
    }
    return 0
}

MoveCurrentWindowToDesktop(desktopNumber) {
    hwnd := WinExist("A")
    if hwnd
        DllCall(MoveWindowToDesktopNumberProc, "ptr", hwnd, "UInt", desktopNumber - 1)
    switchDesktopByNumber(desktopNumber)
}

MoveCurrentWindowToRightDesktop() {
    global CurrentDesktop, DesktopCount
    updateGlobalVariables()
    hwnd := WinExist("A")
    target := CurrentDesktop == DesktopCount ? 1 : CurrentDesktop + 1
    if hwnd
        DllCall(MoveWindowToDesktopNumberProc, "ptr", hwnd, "UInt", target - 1)
    _switchDesktopToTarget(target)
}

MoveCurrentWindowToLeftDesktop() {
    global CurrentDesktop, DesktopCount
    updateGlobalVariables()
    hwnd := WinExist("A")
    target := CurrentDesktop == 1 ? DesktopCount : CurrentDesktop - 1
    if hwnd
        DllCall(MoveWindowToDesktopNumberProc, "ptr", hwnd, "UInt", target - 1)
    _switchDesktopToTarget(target)
}

createVirtualDesktop() {
    global CurrentDesktop, DesktopCount
    Send "#^d"
    DesktopCount += 1
    CurrentDesktop := DesktopCount
    OutputDebug "[create] desktops: " DesktopCount " current: " CurrentDesktop
}

deleteVirtualDesktop() {
    global CurrentDesktop, DesktopCount, LastOpenedDesktop
    Send "#^{F4}"
    if LastOpenedDesktop >= CurrentDesktop
        LastOpenedDesktop -= 1
    DesktopCount -= 1
    CurrentDesktop -= 1
    if CurrentDesktop < 1
        CurrentDesktop := 1
    OutputDebug "[delete] desktops: " DesktopCount " current: " CurrentDesktop
}

; === Binary/Hex helpers ===
HexToBuffer(hex) {
    hex := RegExReplace(hex, "[^A-Fa-f0-9]")
    byteCount := StrLen(hex) // 2
    buf := Buffer(byteCount)
    loop byteCount {
        byteHex := SubStr(hex, (A_Index - 1) * 2 + 1, 2)
        NumPut("UChar", ("0x" byteHex) + 0, buf, A_Index - 1)
    }
    return buf
}

BufferEqual(buf1, off1, buf2, off2, len) {
    loop len {
        b1 := NumGet(buf1, off1 + A_Index - 1, "UChar")
        b2 := NumGet(buf2, off2 + A_Index - 1, "UChar")
        if (b1 != b2)
            return false
    }
    return true
}
