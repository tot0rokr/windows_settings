#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "%A_ScriptDir%\UIA.ahk"

InstallKeybdHook()   ; Win키 같은 걸 더 안정적으로 잡기용 :contentReference[oaicite:1]{index=1}
#UseHook             ; 필요하면 훅 강제 :contentReference[oaicite:2]{index=2}

global overlay := TaskbarNumberOverlay()

; LWin / RWin 둘 다 지원
~*LWin:: {
    overlay.Show()
    KeyWait "LWin"
    overlay.Hide()
}
~*RWin:: {
    overlay.Show()
    KeyWait "RWin"
    overlay.Hide()
}

; 테스트용: 이거 누르면 무조건 뜨게(Win키가 안 잡히는지 확인 가능)
F12::overlay.Show()
F12 Up::overlay.Hide()

class TaskbarNumberOverlay {
    __New() {
        this.gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
        this.gui.BackColor := "EFEFEF"
        WinSetTransColor(this.gui.BackColor, this.gui.Hwnd)
        this.gui.SetFont("s22", "Segoe UI")
        this.labels := []
        this.visible := false
    }

    Show() {
        tbHwnd := WinExist("ahk_class Shell_TrayWnd")
        if !tbHwnd
            return

        ; 작업표시줄 화면 좌표
        WinGetPos &tbX, &tbY, &tbW, &tbH, "ahk_class Shell_TrayWnd"

        ; GUI를 작업표시줄 영역에 딱 맞게
        this.gui.Show(Format("NA x{} y{} w{} h{}", tbX, tbY, tbW, tbH))

        try {
            tbEl := UIA.ElementFromHandle(tbHwnd)
            btns := tbEl.FindAll({ClassName: "Taskbar.TaskListButtonAutomationPeer"})
        } catch as e {
            ToolTip "UIA 에러: " e.Message
            SetTimer () => ToolTip(), -1200
            return
        }

        cnt := btns.Length
        if (cnt = 0) {
            ToolTip "작업표시줄 버튼을 0개로 잡았어 (ClassName 매칭 실패)"
            SetTimer () => ToolTip(), -1200
            return
        }

        max := (cnt < 10) ? cnt : 10  ; Win+1~Win+0(10개)

        while this.labels.Length < max
            this.labels.Push(this.gui.AddText("Center", ""))

        Loop max {
            dy := -Round(8 * (A_ScreenDPI/96))  ; 숫자만 바꾸면 됨(예: -4, -8)
            i := A_Index
            br := btns[i].CurrentBoundingRectangle  ; screen coords {l,t,r,b}
            x := br.l - tbX, y := br.t - tbY + dy
            w := br.r - br.l, h := br.b - br.t

            this.labels[i].Text := (i = 10) ? "0" : i
            this.labels[i].Move(x, y, w, h)
        }

        Loop this.labels.Length - max
            this.labels[max + A_Index].Text := ""

        this.visible := true
    }

    Hide() {
        if this.visible {
            this.gui.Hide()
            this.visible := false
            ToolTip()
        }
    }
}
